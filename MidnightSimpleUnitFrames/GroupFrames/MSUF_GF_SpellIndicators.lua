-- MSUF_GF_SpellIndicators.lua - Group Frames: Per-Spell Indicator Engine
-- Tracks player-cast healer HoTs on party/raid members.
-- 2-tier: placed indicators (icon/square/bar/number) + frame effects (healthtint/border/glow/pulse/namecolor/framealpha).
-- Uses proven HealerBuffs scan pattern (HELPFUL filter, spellId lookup).
-- Called directly from Effects.lua FlushAuraDirty + UpdateAll (no hook wrapping).
-- Multi-spec tracking, zero combat overhead.
-- Midnight 12.0 secret-safe.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end
local SI = GF.SpellIndicators
if not SI then return end

local C_UnitAuras   = _G.C_UnitAuras
local CUA_GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local CUA_GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local CUA_GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local CUA_IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local C_TooltipInfo = _G.C_TooltipInfo
local CreateFrame   = _G.CreateFrame
local UnitExists    = _G.UnitExists
local UnitIsUnit    = _G.UnitIsUnit
local UnitName      = _G.UnitName
local GetTime       = _G.GetTime
local InCombatLockdown = _G.InCombatLockdown
local issecretvalue = _G.issecretvalue
local pairs         = pairs
local type          = type
local ipairs        = ipairs
local select        = select
local tonumber      = tonumber
local math_floor    = math.floor
local math_max      = math.max
local table_sort    = table.sort
local table_concat  = table.concat
local setmetatable  = setmetatable

local function _UnsecretBool(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

-- Reusable tables (cleared per call, zero GC allocation)
local _siBestByType = {}
local _siBestTypes = { "healthtint", "border", "glow", "pulse", "namecolor" }
local _siBestSlots = {
    healthtint = {},
    border = {},
    glow = {},
    pulse = {},
    namecolor = {},
}
local _defaultFrameColor = { 1, 1, 1, 1 }

------------------------------------------------------------------------
-- Compiled lookup: spellId â†’ auraName (rebuilt on spec change)
------------------------------------------------------------------------
local _compiledSpec
local _compiledMultiKey
local _reverseLookup
local _nameLookup
local _auraSpecMap = {} -- auraName â†’ specKey (multi-spec config routing)
local _isMultiMode = false
local _siConfigRev = 1
local _specConfigListCache = setmetatable({}, { __mode = "k" })
local _multiSpecListCache = setmetatable({}, { __mode = "k" })
local _siCachedKind, _siCachedRev, _siCachedConf, _siCachedCfg

local function InvalidateRuntimeCaches()
    _siConfigRev = _siConfigRev + 1
    _compiledSpec = nil
    _compiledMultiKey = nil
    _reverseLookup = nil
    _nameLookup = nil
    _isMultiMode = false
    for k in pairs(_auraSpecMap) do _auraSpecMap[k] = nil end
end

SI.InvalidateRuntimeCaches = InvalidateRuntimeCaches
_G.MSUF_GF_InvalidateSpellIndicatorsRuntimeCaches = InvalidateRuntimeCaches

do
    local oldInvalidate = GF.InvalidateConfCache
    if type(oldInvalidate) == "function" and not GF._msufSIInvalidateWrapped then
        GF._msufSIInvalidateWrapped = true
        GF.InvalidateConfCache = function(...)
            InvalidateRuntimeCaches()
            return oldInvalidate(...)
        end
        _G.MSUF_GF_InvalidateConfCache = GF.InvalidateConfCache
    end
end

local function GetMultiSpecList(siCfg)
    local ms = siCfg and siCfg.multiSpecs
    if not ms then return nil, 0, nil end

    local cached = _multiSpecListCache[siCfg]
    if cached and cached.rev == _siConfigRev and cached.source == ms then
        return cached.list, cached.count, cached.key
    end

    local list, count = {}, 0
    for sk in pairs(ms) do
        count = count + 1
        list[count] = sk
    end
    if count > 1 then table_sort(list) end

    local key = table_concat(list, ",")
    _multiSpecListCache[siCfg] = {
        rev = _siConfigRev,
        source = ms,
        list = list,
        count = count,
        key = key,
    }
    return list, count, key
end

local function CompileLookup(specKey, siCfg)
    if specKey ~= "multi" then
        -- Single-spec mode
        if specKey == _compiledSpec and _reverseLookup and not _isMultiMode then return end
        _compiledSpec     = specKey
        _compiledMultiKey = nil
        _isMultiMode      = false
        _reverseLookup    = SI.BuildReverseLookup(specKey)
        _nameLookup       = SI.BuildNameLookup and SI.BuildNameLookup(specKey) or nil
        for k in pairs(_auraSpecMap) do _auraSpecMap[k] = nil end
        return
    end
    -- Multi-spec mode
    local parts, count, key = GetMultiSpecList(siCfg)
    if not parts or count <= 0 then return end
    if key == _compiledMultiKey and _reverseLookup and _isMultiMode then return end
    _compiledMultiKey = key
    _compiledSpec     = nil
    _isMultiMode      = true
    _reverseLookup    = {}
    _nameLookup       = nil
    for k in pairs(_auraSpecMap) do _auraSpecMap[k] = nil end
    for pi = 1, count do
        local sk = parts[pi]
        local ids = SI.SpellIDs[sk]
        if ids then
            for auraName, spellId in pairs(ids) do
                if not _reverseLookup[spellId] then
                    _reverseLookup[spellId] = auraName
                    _auraSpecMap[auraName] = _auraSpecMap[auraName] or sk
                end
            end
        end
        local alts = SI.AltSpellIDs[sk]
        if alts then
            for altId, auraName in pairs(alts) do
                if not _reverseLookup[altId] then
                    _reverseLookup[altId] = auraName
                    _auraSpecMap[auraName] = _auraSpecMap[auraName] or sk
                end
            end
        end
        local secrets = SI.SecretSpellIDs[sk]
        if secrets then
            for auraName, spellId in pairs(secrets) do
                if not _reverseLookup[spellId] then
                    _reverseLookup[spellId] = auraName
                    _auraSpecMap[auraName] = _auraSpecMap[auraName] or sk
                end
            end
        end
        local nl = SI.BuildNameLookup and SI.BuildNameLookup(sk)
        if nl then
            if not _nameLookup then _nameLookup = {} end
            for name, auraKey in pairs(nl) do
                if not _nameLookup[name] then
                    _nameLookup[name] = auraKey
                    _auraSpecMap[auraKey] = _auraSpecMap[auraKey] or sk
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Config helpers
------------------------------------------------------------------------
local function GetSIConfig(kind)
    if kind == _siCachedKind and _siCachedRev == _siConfigRev then
        return _siCachedCfg
    end
    local conf = GF.GetConf(kind)
    _siCachedKind = kind
    _siCachedRev = _siConfigRev
    _siCachedConf = conf
    _siCachedCfg = conf and conf.spellIndicators or nil
    return _siCachedCfg
end

local function ResolveSpec(siCfg)
    if not siCfg then return nil end
    local spec = siCfg.spec or "auto"
    if spec == "multi" then
        local _, count = GetMultiSpecList(siCfg)
        if count > 0 then return "multi" end
        return nil
    end
    if spec == "auto" then return SI.GetPlayerSpec() end
    return spec
end

local function ResolveRuntimeSpec(siCfg, playerSpec)
    if not (siCfg and siCfg.enabled == true) then return nil end
    playerSpec = playerSpec or SI.GetPlayerSpec()
    if not playerSpec then return nil end

    local spec = siCfg.spec or "auto"
    if spec == "auto" then return playerSpec end
    if spec == "multi" then
        local ms = siCfg.multiSpecs
        return (ms and ms[playerSpec] == true) and playerSpec or nil
    end
    return (spec == playerSpec) and spec or nil
end

local function SpecConfigHasRuntimeWork(siCfg, specKey)
    if not (siCfg and specKey and SI.TrackableAuras and SI.TrackableAuras[specKey]) then return false end

    local specCfg = siCfg.specs and siCfg.specs[specKey]
    if not specCfg then
        return SI.SpecDefaults and SI.SpecDefaults[specKey] ~= nil
    end

    local sawEntry = false
    for _, auraCfg in pairs(specCfg) do
        sawEntry = true
        if type(auraCfg) == "table" and auraCfg.enabled ~= false then
            return true
        end
    end
    if not sawEntry then
        return SI.SpecDefaults and SI.SpecDefaults[specKey] ~= nil
    end
    return false
end

local _runtimeActiveCache = setmetatable({}, { __mode = "k" })

function SI.IsRuntimeActive(kind, siCfg)
    if not (siCfg and siCfg.enabled == true) then return false end

    local playerSpec = SI.GetPlayerSpec()
    if not playerSpec then return false end

    local cached = _runtimeActiveCache[siCfg]
    if cached
        and cached.rev == _siConfigRev
        and cached.playerSpec == playerSpec
        and cached.spec == siCfg.spec
        and cached.multiSpecs == siCfg.multiSpecs
    then
        return cached.active
    end

    local specKey = ResolveRuntimeSpec(siCfg, playerSpec)
    local active = specKey and SpecConfigHasRuntimeWork(siCfg, specKey) or false
    _runtimeActiveCache[siCfg] = {
        rev = _siConfigRev,
        playerSpec = playerSpec,
        spec = siCfg.spec,
        multiSpecs = siCfg.multiSpecs,
        active = active and true or false,
    }
    return active and true or false
end

GF.SpellIndicatorsRuntimeActive = function(kind, siCfg)
    return SI.IsRuntimeActive(kind, siCfg)
end

do
    local specFrame = CreateFrame and CreateFrame("Frame")
    if specFrame then
        local function RefreshRuntimeState()
            InvalidateRuntimeCaches()
            if InCombatLockdown and InCombatLockdown() then
                if GF.MarkAllDirty then GF.MarkAllDirty(GF.DIRTY_AURAS or GF.DIRTY_ALL or 0x3F) end
                return
            end

            if GF.ForEachFrame and GF.BuildFrameCache and GF.RegisterUnitEvents then
                GF.ForEachFrame(function(f)
                    if f and f._msufIsGroupFrame then
                        GF.BuildFrameCache(f)
                        if f.unit then GF.RegisterUnitEvents(f, f.unit) end
                        if f._c and not f._c.siEn and GF.HideSpellIndicators then
                            GF.HideSpellIndicators(f)
                        end
                    end
                end)
            elseif GF.MarkAllDirty then
                GF.MarkAllDirty(GF.DIRTY_AURAS or GF.DIRTY_ALL or 0x3F)
            end
        end

        specFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        specFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        specFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
        specFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        specFrame:SetScript("OnEvent", function(_, event, unit)
            if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
            RefreshRuntimeState()
        end)
    end
end

------------------------------------------------------------------------
-- Auto-populate defaults for a spec (one-time, cold path)
------------------------------------------------------------------------
local function EnsureSpecConfig(siCfg, specKey)
    if not siCfg or not specKey then return nil end
    siCfg.specs = siCfg.specs or {}
    local defaults = SI.SpecDefaults[specKey]

    local function DeepCopy(src)
        if type(src) ~= "table" then return src end
        local dst = {}
        for k, v in pairs(src) do
            dst[k] = DeepCopy(v)
        end
        return dst
    end

    local specCfg = siCfg.specs[specKey]
    if not specCfg then
        specCfg = {}
        siCfg.specs[specKey] = specCfg
    end
    if not defaults then return specCfg end

    for auraName, def in pairs(defaults) do
        local entry = specCfg[auraName]
        if not entry then
            entry = DeepCopy(def)
            if entry.onlyOwn == nil then entry.onlyOwn = true end
            specCfg[auraName] = entry
        else
            if entry.placed == nil and def.placed ~= nil then
                entry.placed = DeepCopy(def.placed)
            end
            if entry.frame == nil and def.frame ~= nil then
                entry.frame = DeepCopy(def.frame)
            end
            if entry.onlyOwn == nil then entry.onlyOwn = (def.onlyOwn ~= false) end
        end
    end

    return specCfg
end

function SI.EnsureSpecConfig(siCfg, specKey)
    return EnsureSpecConfig(siCfg, specKey)
end

local function GetSpecConfigList(siCfg, specKey)
    local specCfg = EnsureSpecConfig(siCfg, specKey)
    if not specCfg then return nil, 0, nil end

    local cached = _specConfigListCache[specCfg]
    if cached and cached.rev == _siConfigRev then
        return cached.list, cached.count, specCfg
    end

    local list, count = {}, 0
    for auraName, auraCfg in pairs(specCfg) do
        count = count + 1
        list[count] = { name = auraName, cfg = auraCfg }
    end

    _specConfigListCache[specCfg] = {
        rev = _siConfigRev,
        list = list,
        count = count,
    }
    return list, count, specCfg
end

------------------------------------------------------------------------
-- Scan: player-cast auras by C-side filter, optional all-caster fallback
------------------------------------------------------------------------
local _slotBuf = {}
local _slotCount = 0
local HELPFUL_ALL = "HELPFUL"
local HELPFUL_PLAYER = "HELPFUL|PLAYER"
local SECRET_FILTER_RAID = "PLAYER|HELPFUL|RAID"
local SECRET_FILTER_RIC  = "PLAYER|HELPFUL|RAID_IN_COMBAT"
local SECRET_FILTER_EXT  = "PLAYER|HELPFUL|EXTERNAL_DEFENSIVE"
local SECRET_FILTER_DISP = "PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE"
local _secretSignatureCache = {}

local function CaptureSlots(...)
    local count = select("#", ...)
    for i = 1, count do _slotBuf[i] = select(i, ...) end
    for i = count + 1, _slotCount do _slotBuf[i] = nil end
    _slotCount = count
    return _slotBuf, count
end

local function SIQuerySlots(unit, filter, maxCount)
    if GF and GF.QueryAuraSlots then
        return GF.QueryAuraSlots(unit, filter, maxCount)
    end
    if not CUA_GetAuraSlots and C_UnitAuras then CUA_GetAuraSlots = C_UnitAuras.GetAuraSlots end
    if not CUA_GetAuraSlots then return _slotBuf, 0 end
    if maxCount then
        return CaptureSlots(CUA_GetAuraSlots(unit, filter, maxCount))
    end
    return CaptureSlots(CUA_GetAuraSlots(unit, filter))
end

local function SIQueryAuraData(unit, slot)
    if GF and GF.GetAuraDataBySlot then
        return GF.GetAuraDataBySlot(unit, slot)
    end
    if not CUA_GetAuraDataBySlot and C_UnitAuras then CUA_GetAuraDataBySlot = C_UnitAuras.GetAuraDataBySlot end
    return CUA_GetAuraDataBySlot and CUA_GetAuraDataBySlot(unit, slot)
end

local function SIQueryAuraDataByIndex(unit, index, filter)
    if not CUA_GetAuraDataByIndex and C_UnitAuras then CUA_GetAuraDataByIndex = C_UnitAuras.GetAuraDataByIndex end
    return CUA_GetAuraDataByIndex and CUA_GetAuraDataByIndex(unit, index, filter)
end

local function UnitIsPlayerUnit(unit)
    if unit == "player" then return true end
    if not (unit and UnitIsUnit) then return false end
    return _UnsecretBool(UnitIsUnit(unit, "player")) == true
end

local _linkedTooltipCache = {}
local _linkedSourceAuraCache = {}
local _linkedTargetIDSetCache = {}

local function GetLinkedTargetIDSet(specKey, auraName, rule)
    local key = specKey .. ":" .. auraName
    local cached = _linkedTargetIDSetCache[key]
    if cached and cached.source == rule.targetSpellIDs then return cached.set end

    local set, ids = {}, rule and rule.targetSpellIDs
    if type(ids) == "table" then
        for i = 1, #ids do
            local id = tonumber(ids[i])
            if id then set[id] = true end
        end
    end
    cached = {
        source = ids,
        set = set,
    }
    _linkedTargetIDSetCache[key] = cached
    return set
end

local function FindHelpfulAuraBySpellID(unit, spellID)
    if not (unit and spellID) then return nil end
    for i = 1, 40 do
        local aura = SIQueryAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then break end
        local sid = aura.spellId
        if sid ~= nil and not (issecretvalue and issecretvalue(sid)) then
            sid = tonumber(sid)
            if sid == spellID then return aura end
        end
    end
    return nil
end

local function MatchLinkedTargetAuraByID(spellID, specKey, siCfg)
    if not (spellID and SI.LinkedAuraRules) then return nil end

    if specKey ~= "multi" then
        local rules = SI.LinkedAuraRules[specKey]
        if not rules then return nil end
        for auraName, rule in pairs(rules) do
            if _scanOnlyOwnByAura[auraName] ~= nil then
                local targetIDs = GetLinkedTargetIDSet(specKey, auraName, rule)
                if targetIDs and targetIDs[spellID] then return auraName end
            end
        end
        return nil
    end

    local specs, specCount = GetMultiSpecList(siCfg)
    if not specs then return nil end

    local matched
    for i = 1, specCount do
        local sk = specs[i]
        local rules = SI.LinkedAuraRules[sk]
        if rules then
            for auraName, rule in pairs(rules) do
                if _scanOnlyOwnByAura[auraName] ~= nil then
                    local targetIDs = GetLinkedTargetIDSet(sk, auraName, rule)
                    if targetIDs and targetIDs[spellID] then
                        if matched and matched ~= auraName then return nil end
                        matched = auraName
                    end
                end
            end
        end
    end
    return matched
end

local function FindPlayerSourceAuraCached(spellID)
    if not spellID then return nil end
    local now = GetTime and GetTime() or 0
    local cached = _linkedSourceAuraCache[spellID]
    if cached and (now - (cached.time or 0)) < 0.05 then
        return cached.aura
    end
    local aura = FindHelpfulAuraBySpellID("player", spellID)
    _linkedSourceAuraCache[spellID] = {
        aura = aura,
        time = now,
    }
    return aura
end

local function ResolveLinkedTooltipTargetName(sourceAura, rule)
    if not C_TooltipInfo then C_TooltipInfo = _G.C_TooltipInfo end
    if not (sourceAura and sourceAura.auraInstanceID and C_TooltipInfo and C_TooltipInfo.GetUnitAura) then
        return nil
    end
    local cacheKey = tostring(rule and rule.sourceSpellID or "") .. ":" .. tostring(sourceAura.auraInstanceID)
    local now = GetTime and GetTime() or 0
    local cached = _linkedTooltipCache[cacheKey]
    if cached and (now - (cached.time or 0)) < 0.25 then
        return cached.targetName
    end

    local auraIndex
    for i = 1, 40 do
        local aura = SIQueryAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        if aura.auraInstanceID == sourceAura.auraInstanceID then
            auraIndex = i
            break
        end
    end
    if not auraIndex then return nil end

    local tooltip = C_TooltipInfo.GetUnitAura("player", auraIndex, "HELPFUL")
    local lines = tooltip and tooltip.lines
    if type(lines) ~= "table" then return nil end

    for i = 1, #lines do
        local text = lines[i] and lines[i].leftText
        if text and UnitName then
            for p = 1, 4 do
                local partyUnit = "party" .. p
                local partyName = UnitExists(partyUnit) and UnitName(partyUnit)
                if partyName and partyName ~= "" and text:find(partyName, 1, true) then
                    _linkedTooltipCache[cacheKey] = {
                        targetName = partyName,
                        time = now,
                    }
                    return partyName
                end
            end
            for r = 1, 40 do
                local raidUnit = "raid" .. r
                local raidName = UnitExists(raidUnit) and UnitName(raidUnit)
                if raidName and raidName ~= "" and text:find(raidName, 1, true) then
                    _linkedTooltipCache[cacheKey] = {
                        targetName = raidName,
                        time = now,
                    }
                    return raidName
                end
            end
        end
    end

    return nil
end

local function MakeLinkedAuraData(sourceAura, auraName, rule)
    return {
        spellId = rule and rule.sourceSpellID or 0,
        icon = SI.IconTextures and SI.IconTextures[auraName] or (sourceAura and sourceAura.icon),
        duration = sourceAura and sourceAura.duration,
        expirationTime = sourceAura and sourceAura.expirationTime,
        applications = sourceAura and sourceAura.applications or 0,
        sourceUnit = "player",
        auraInstanceID = sourceAura and sourceAura.auraInstanceID,
        linked = true,
    }
end

local function ApplyLinkedAurasForSpec(unit, specKey)
    local rules = SI.LinkedAuraRules and SI.LinkedAuraRules[specKey]
    if not rules then return end

    for auraName, rule in pairs(rules) do
        if not _scanResults[auraName] and _scanOnlyOwnByAura[auraName] ~= nil then
            if not UnitIsPlayerUnit(unit) then
                local sourceAura = FindPlayerSourceAuraCached(rule and rule.sourceSpellID)
                local targetName = sourceAura and ResolveLinkedTooltipTargetName(sourceAura, rule)
                local unitName = targetName and UnitName and UnitName(unit)
                if unitName and unitName == targetName then
                    _scanResults[auraName] = MakeLinkedAuraData(sourceAura, auraName, rule)
                end
            end
        end
    end
end

local function ApplyLinkedAuras(unit, specKey, siCfg)
    if not SI.LinkedAuraRules then return end
    if specKey ~= "multi" then
        ApplyLinkedAurasForSpec(unit, specKey)
        return
    end

    local specs, specCount = GetMultiSpecList(siCfg)
    if not specs then return end
    for i = 1, specCount do
        ApplyLinkedAurasForSpec(unit, specs[i])
    end
end

local function NeedsLinkedAuraScan(siCfg, specKey)
    if not SI.LinkedAuraRules then return false end
    if specKey == "multi" then
        local specs, specCount = GetMultiSpecList(siCfg)
        if not specs then return false end
        for i = 1, specCount do
            local rules = SI.LinkedAuraRules[specs[i]]
            if rules then
                for auraName in pairs(rules) do
                    if _scanOnlyOwnByAura[auraName] ~= nil then return true end
                end
            end
        end
        return false
    end

    local rules = SI.LinkedAuraRules[specKey]
    if not rules then return false end
    for auraName in pairs(rules) do
        if _scanOnlyOwnByAura[auraName] ~= nil then return true end
    end
    return false
end

local function SecretFilterPasses(unit, auraInstanceID, filter)
    if not CUA_IsAuraFilteredOutByInstanceID and C_UnitAuras then
        CUA_IsAuraFilteredOutByInstanceID = C_UnitAuras.IsAuraFilteredOutByInstanceID
    end
    if not (CUA_IsAuraFilteredOutByInstanceID and unit and auraInstanceID) then return false end
    if issecretvalue and issecretvalue(auraInstanceID) then return false end

    local filtered = CUA_IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
    if filtered == nil or (issecretvalue and issecretvalue(filtered)) then return false end
    return filtered == false
end

local function NormalizeSecretMatch(specKey, auraName, unit)
    if not auraName then return nil end
    if specKey == "AugmentationEvoker" and auraName == "SensePower" and UnitIsPlayerUnit(unit) then
        return "EbonMight"
    end
    if specKey == "PreservationEvoker" and auraName == "VerdantEmbrace" and UnitIsPlayerUnit(unit) then
        return "Lifebind"
    end
    return auraName
end

local function MakeSecretSignature(unit, aura)
    if not (unit and aura) then return nil end
    local auraInstanceID = aura.auraInstanceID
    if not auraInstanceID then return nil end

    local raid = SecretFilterPasses(unit, auraInstanceID, SECRET_FILTER_RAID) and "1" or "0"
    local ric  = SecretFilterPasses(unit, auraInstanceID, SECRET_FILTER_RIC) and "1" or "0"
    local ext  = SecretFilterPasses(unit, auraInstanceID, SECRET_FILTER_EXT) and "1" or "0"
    local disp = SecretFilterPasses(unit, auraInstanceID, SECRET_FILTER_DISP) and "1" or "0"
    return raid .. ":" .. ric .. ":" .. ext .. ":" .. disp
end

local function GetSecretSignatureLookup(specKey)
    local info = SI.SecretAuraInfo and SI.SecretAuraInfo[specKey]
    if not info then return nil end

    local cached = _secretSignatureCache[specKey]
    if cached and cached.source == info then return cached.lookup end

    local lookup, any = {}, false
    for auraName, auraInfo in pairs(info) do
        local signature = auraInfo and auraInfo.signature
        if type(signature) == "string" and signature ~= "" then
            lookup[signature] = auraName
            any = true
        end
    end

    cached = {
        source = info,
        lookup = any and lookup or nil,
    }
    _secretSignatureCache[specKey] = cached
    return cached.lookup
end

local function MatchSecretAuraSignature(unit, aura, specKey, siCfg)
    if not (SI.SecretAuraInfo and CUA_IsAuraFilteredOutByInstanceID) and not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID) then
        return nil
    end
    if aura then
        local sid = aura.spellId
        if sid ~= nil and not (issecretvalue and issecretvalue(sid)) then
            return nil
        end
    end

    if specKey ~= "multi" then
        local lookup = GetSecretSignatureLookup(specKey)
        if not lookup then return nil end
        local signature = MakeSecretSignature(unit, aura)
        if not signature then return nil end
        return lookup and NormalizeSecretMatch(specKey, lookup[signature], unit) or nil
    end

    local specs, specCount = GetMultiSpecList(siCfg)
    if not specs then return nil end

    local signature
    local matched
    for i = 1, specCount do
        local lookup = GetSecretSignatureLookup(specs[i])
        if lookup then
            signature = signature or MakeSecretSignature(unit, aura)
            if not signature then return nil end
            local auraName = NormalizeSecretMatch(specs[i], lookup[signature], unit)
            if auraName then
                if matched and matched ~= auraName then
                    return nil
                end
                matched = auraName
            end
        end
    end
    return matched
end

local function MatchSelfOnlyAura(unit, aura, specKey, siCfg)
    if not (SI.SelfOnlySpellIDs and aura) then return nil end
    local sid = aura.spellId
    if sid == nil or (issecretvalue and issecretvalue(sid)) then return nil end
    sid = tonumber(sid)
    if not sid then return nil end

    if specKey ~= "multi" then
        local selfOnly = SI.SelfOnlySpellIDs[specKey]
        local auraName = selfOnly and selfOnly[sid]
        if not auraName then return nil end
        return UnitIsPlayerUnit(unit) and auraName or nil
    end

    local specs, specCount = GetMultiSpecList(siCfg)
    if not specs then return nil end

    local matched
    for i = 1, specCount do
        local selfOnly = SI.SelfOnlySpellIDs[specs[i]]
        local auraName = selfOnly and selfOnly[sid]
        if auraName then
            if matched and matched ~= auraName then
                return nil
            end
            matched = auraName
        end
    end
    return matched and UnitIsPlayerUnit(unit) and matched or nil
end

local _scanResults = {}
local _scanOnlyOwnByAura = {}

local function MarkScanAuraConfig(auraName, auraCfg)
    if not auraCfg or auraCfg.enabled == false then return false end
    if auraCfg.onlyOwn == false then
        _scanOnlyOwnByAura[auraName] = false
        return true
    end
    if _scanOnlyOwnByAura[auraName] == nil then
        _scanOnlyOwnByAura[auraName] = true
    end
    return false
end

local function BuildScanConfig(siCfg, specKey)
    for k in pairs(_scanOnlyOwnByAura) do _scanOnlyOwnByAura[k] = nil end
    local wantsAllCasters = false

    if specKey == "multi" then
        local specs, specCount = GetMultiSpecList(siCfg)
        if specs then
            for si = 1, specCount do
                local specList, auraCount = GetSpecConfigList(siCfg, specs[si])
                if specList then
                    for ai = 1, auraCount do
                        local item = specList[ai]
                        if MarkScanAuraConfig(item.name, item.cfg) then wantsAllCasters = true end
                    end
                end
            end
        end
    else
        local specList, auraCount = GetSpecConfigList(siCfg, specKey)
        if specList then
            for ai = 1, auraCount do
                local item = specList[ai]
                if MarkScanAuraConfig(item.name, item.cfg) then wantsAllCasters = true end
            end
        end
    end

    return wantsAllCasters
end

local function NeedsSecretSignatureScan(siCfg, specKey)
    if not SI.SecretAuraInfo then return false end
    if not CUA_IsAuraFilteredOutByInstanceID and C_UnitAuras then
        CUA_IsAuraFilteredOutByInstanceID = C_UnitAuras.IsAuraFilteredOutByInstanceID
    end
    if not CUA_IsAuraFilteredOutByInstanceID then return false end

    if specKey == "multi" then
        local specs, specCount = GetMultiSpecList(siCfg)
        if not specs then return false end
        for i = 1, specCount do
            local info = SI.SecretAuraInfo[specs[i]]
            if info then
                for auraName in pairs(info) do
                    if _scanOnlyOwnByAura[auraName] ~= nil then return true end
                end
            end
        end
        return false
    end

    local info = SI.SecretAuraInfo[specKey]
    if not info then return false end
    for auraName in pairs(info) do
        if _scanOnlyOwnByAura[auraName] ~= nil then return true end
    end
    return false
end

local function NeedsSelfOnlyScan(siCfg, specKey)
    if not SI.SelfOnlySpellIDs then return false end
    if specKey == "multi" then
        local specs, specCount = GetMultiSpecList(siCfg)
        if not specs then return false end
        for i = 1, specCount do
            local selfOnly = SI.SelfOnlySpellIDs[specs[i]]
            if selfOnly then
                for _, auraName in pairs(selfOnly) do
                    if _scanOnlyOwnByAura[auraName] ~= nil then return true end
                end
            end
        end
        return false
    end

    local selfOnly = SI.SelfOnlySpellIDs[specKey]
    if not selfOnly then return false end
    for _, auraName in pairs(selfOnly) do
        if _scanOnlyOwnByAura[auraName] ~= nil then return true end
    end
    return false
end

local function ScanAuraSlots(unit, filter, fromPlayerFilter, specKey, siCfg)
    local slots, count = SIQuerySlots(unit, filter)
    for i = 2, count do
        local aura = SIQueryAuraData(unit, slots[i])
        if aura then
            local sid = aura.spellId
            local matched
            local matchedBySignature = false
            local matchedBySelfOnly = false
            local matchedByLinkedTarget = false
            -- Secret-safety guard + tag-strip: secret-tagged integers need
            -- tonumber() before use as hash key (Midnight 12.0 semantics).
            if sid ~= nil and not (issecretvalue and issecretvalue(sid)) then
                sid = tonumber(sid)
                if sid then
                    matched = _reverseLookup[sid]
                    local linkedTargetMatched = MatchLinkedTargetAuraByID(sid, specKey, siCfg)
                    if linkedTargetMatched then
                        matched = linkedTargetMatched
                        matchedByLinkedTarget = true
                    end
                end
            end
            if not matched and _nameLookup then
                local aName = aura.name
                if aName ~= nil and not (issecretvalue and issecretvalue(aName)) then
                    matched = _nameLookup[aName]
                end
            end
            local selfOnlyMatched = MatchSelfOnlyAura(unit, aura, specKey, siCfg)
            if selfOnlyMatched then
                matched = selfOnlyMatched
                matchedBySelfOnly = true
            end
            if not matched then
                matched = MatchSecretAuraSignature(unit, aura, specKey, siCfg)
                matchedBySignature = matched ~= nil
            end
            if matched and not _scanResults[matched] then
                local onlyOwn = _scanOnlyOwnByAura[matched]
                if onlyOwn ~= nil and (fromPlayerFilter or onlyOwn == false or matchedBySignature or matchedBySelfOnly or matchedByLinkedTarget) then
                    _scanResults[matched] = aura
                end
            end
        end
    end
end

local function ScanUnit(unit, kind, siCfg, specKey)
    for k in pairs(_scanResults) do _scanResults[k] = nil end
    if not _reverseLookup then return end
    if (not CUA_GetAuraSlots or not CUA_GetAuraDataBySlot) and C_UnitAuras then
        CUA_GetAuraSlots = CUA_GetAuraSlots or C_UnitAuras.GetAuraSlots
        CUA_GetAuraDataBySlot = CUA_GetAuraDataBySlot or C_UnitAuras.GetAuraDataBySlot
    end
    if not (CUA_GetAuraSlots and CUA_GetAuraDataBySlot) then return end

    local wantsAllCasters = BuildScanConfig(siCfg, specKey)
    local wantsSecretSignatureScan = NeedsSecretSignatureScan(siCfg, specKey)
    local wantsSelfOnlyScan = NeedsSelfOnlyScan(siCfg, specKey)
    local wantsLinkedAuraScan = NeedsLinkedAuraScan(siCfg, specKey)
    ScanAuraSlots(unit, HELPFUL_PLAYER, true, specKey, siCfg)
    if wantsAllCasters or wantsSecretSignatureScan or wantsSelfOnlyScan or wantsLinkedAuraScan then
        ScanAuraSlots(unit, HELPFUL_ALL, false, specKey, siCfg)
    end
    if wantsLinkedAuraScan then
        ApplyLinkedAuras(unit, specKey, siCfg)
    end
end

local function SpecConfigHasFrameEffects(siCfg, specKey)
    local specCfg = siCfg and siCfg.specs and siCfg.specs[specKey]
    if specCfg then
        for _, cfg in pairs(specCfg) do
            local frame = cfg and cfg.enabled ~= false and cfg.frame
            if frame and frame.type and frame.type ~= "none" then return true end
        end
    end

    local defaults = SI.SpecDefaults and SI.SpecDefaults[specKey]
    if not defaults then return false end
    for auraName, def in pairs(defaults) do
        local cfg = specCfg and specCfg[auraName]
        if not cfg then cfg = def end
        local frame = cfg and cfg.enabled ~= false and cfg.frame
        if frame and frame.type and frame.type ~= "none" then return true end
    end
    return false
end

local function NeedsAmbiguousAddedAuraScan(siCfg, specKey)
    if not siCfg or not specKey then return false end
    if specKey == "multi" then
        local specs, specCount = GetMultiSpecList(siCfg)
        if not specs then return false end
        for i = 1, specCount do
            local sk = specs[i]
            if SI.SecretSpellIDs and SI.SecretSpellIDs[sk] then return true end
            if SpecConfigHasFrameEffects(siCfg, sk) then return true end
        end
        return false
    end
    if SI.SecretSpellIDs and SI.SecretSpellIDs[specKey] then return true end
    return SpecConfigHasFrameEffects(siCfg, specKey)
end

function GF.SpellIndicatorsUnitAuraRelevant(f, unit, kind, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return true end

    local siCfg = GetSIConfig(kind or (f and f._msufGFKind) or "party")
    if not siCfg or not siCfg.enabled then return false end

    local specKey = ResolveRuntimeSpec(siCfg)
    if not specKey then return false end
    CompileLookup(specKey, siCfg)

    local added = updateInfo.addedAuras
    if added then
        local ambiguousAddedAura = false
        for i = 1, #added do
            local aura = added[i]
            if aura then
                local sid = aura.spellId
                local auraName = aura.name
                if sid == nil and auraName == nil then
                    ambiguousAddedAura = true
                end
                if sid ~= nil and issecretvalue and issecretvalue(sid) then
                    ambiguousAddedAura = true
                elseif sid ~= nil then
                    sid = tonumber(sid)
                    if sid and _reverseLookup and _reverseLookup[sid] then return true end
                end
                if auraName ~= nil and issecretvalue and issecretvalue(auraName) then
                    ambiguousAddedAura = true
                elseif _nameLookup and auraName ~= nil then
                    if _nameLookup[auraName] then
                        return true
                    end
                end
            end
        end
        if ambiguousAddedAura and NeedsAmbiguousAddedAuraScan(siCfg, specKey) then
            return true
        end
    end

    local tracked = f and f._msufSIDedupIDs
    if not tracked then return false end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated then
        for i = 1, #updated do
            if tracked[updated[i]] then return true end
        end
    end

    local removed = updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            if tracked[removed[i]] then return true end
        end
    end

    if InCombatLockdown and InCombatLockdown() and NeedsAmbiguousAddedAuraScan(siCfg, specKey) then
        local hasDelta = (added and #added > 0)
            or (updated and #updated > 0)
            or (removed and #removed > 0)
        if hasDelta then return true end
    end

    return false
end

local function ResolveCooldownFontString(cd)
    if not cd then return nil end
    local cached = cd._msufCooldownFontString
    if cached and cached ~= false then return cached end

    local retryAt = cd._msufCooldownFontStringRetryAt
    local now = GetTime()
    if type(retryAt) == "number" and now < retryAt then
        return nil
    end

    if cd.EnumerateRegions then
        for region in cd:EnumerateRegions() do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                cd._msufCooldownFontString = region
                cd._msufCooldownFontStringRetryAt = nil
                return region
            end
        end
    end

    cd._msufCooldownFontStringRetryAt = now + 0.50
    cd._msufCooldownFontString = false
    return nil
end

local function ResolveCooldownBaseColor()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    if g and g.useCustomFontColor == true then
        local r = g.fontColorCustomR
        local gg = g.fontColorCustomG
        local b = g.fontColorCustomB
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b, 1
        end
    end
    return 1, 1, 1, 1
end

local function ApplyPlacedCooldownStyle(cd, ownerFrame, numberOnly)
    if not cd then return end
    local kind = (ownerFrame and ownerFrame._msufGFKind) or "party"
    local conf = GF.GetConf and GF.GetConf(kind)
    local reverse = (not numberOnly) and conf and conf.cooldownSwipeDarkenOnLoss == true or false

    if cd._msufGFSIDrawEdge ~= false then
        cd._msufGFSIDrawEdge = false
        cd:SetDrawEdge(false)
    end
    if cd.SetDrawBling and cd._msufGFSIDrawBling ~= false then
        cd._msufGFSIDrawBling = false
        cd:SetDrawBling(false)
    end
    local wantSwipe = not numberOnly
    if cd._msufGFSIDrawSwipe ~= wantSwipe then
        cd._msufGFSIDrawSwipe = wantSwipe
        cd:SetDrawSwipe(wantSwipe)
    end
    if cd._msufGFSIReverse ~= reverse then
        cd._msufGFSIReverse = reverse
        cd:SetReverse(reverse)
    end
end

local function ClearA2CooldownScope(ind)
    if not ind then return end
    ind._msufA2_cdDurationObj = nil
    ind._msufA2_durationObj = nil
    ind._msufA2_cdMgrRegistered = nil
    ind._msufA2_cdPending = nil
    ind._msufA2_hideCDNumbers = nil
    local cd = ind.cooldown
    if cd then
        cd._msufA2_durationObj = nil
    end
end

local function ApplyPlacedCooldownFont(ind, cfg, fontSizeOverride)
    local cd = ind and ind.cooldown
    if not cd then return nil end

    local fs = ResolveCooldownFontString(cd)
    if not fs then return nil end

    local cdSize = fontSizeOverride or cfg.cooldownSize or 8
    local gfs = _G.MSUF_GetGlobalFontSettings
    local fp, ff
    if type(gfs) == "function" then fp, ff = gfs() end
    if not fp then
        fp = GF and GF.ResolveFontPath and GF.ResolveFontPath() or "Fonts\\FRIZQT__.TTF"
        ff = GF and GF.ResolveFontFlags and GF.ResolveFontFlags() or "OUTLINE"
    end
    local wantFlags = cfg.cooldownOutline or ff or "OUTLINE"
    if cd._msufGFCdTextSize ~= cdSize or cd._msufGFCdFontPath ~= fp
        or cd._msufGFCdFontFlags ~= wantFlags
    then
        fs:SetFont(fp, cdSize, wantFlags)
        cd._msufGFCdTextSize = cdSize
        cd._msufGFCdFontPath = fp
        cd._msufGFCdFontFlags = wantFlags
    end
    if cd._msufGFCdAnchor ~= "CENTER" or cd._msufGFCdOX ~= 0 or cd._msufGFCdOY ~= 0 then
        cd._msufGFCdAnchor = "CENTER"
        cd._msufGFCdOX = 0
        cd._msufGFCdOY = 0
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", ind, "CENTER", 0, 0)
    end

    local r, g, b, a = ResolveCooldownBaseColor()
    if cd._msufGFCdColorR ~= r or cd._msufGFCdColorG ~= g
        or cd._msufGFCdColorB ~= b or cd._msufGFCdColorA ~= a
    then
        cd._msufGFCdColorR = r
        cd._msufGFCdColorG = g
        cd._msufGFCdColorB = b
        cd._msufGFCdColorA = a
        if fs.SetTextColor then
            fs:SetTextColor(r, g, b, a)
        elseif fs.SetVertexColor then
            fs:SetVertexColor(r, g, b, a)
        end
    end

    return fs
end

local function ApplyPreviewTextStyle(fs, cfg, fallbackSize, forceFallbackSize)
    if not fs then return end
    local gfs = _G.MSUF_GetGlobalFontSettings
    local fp, ff
    if type(gfs) == "function" then fp, ff = gfs() end
    if not fp then
        fp = GF and GF.ResolveFontPath and GF.ResolveFontPath() or "Fonts\\FRIZQT__.TTF"
        ff = GF and GF.ResolveFontFlags and GF.ResolveFontFlags() or "OUTLINE"
    end
    local fontSize = forceFallbackSize and fallbackSize or (cfg.cooldownSize or fallbackSize or 8)
    fs:SetFont(fp, fontSize or 8, cfg.cooldownOutline or ff or "OUTLINE")
    local r, g, b, a = ResolveCooldownBaseColor()
    fs:SetTextColor(r, g, b, a)
end

local function SetShownIfChanged(region, shown)
    if not region then return end
    shown = shown and true or false
    if region.IsShown and region:IsShown() == shown then return end
    if shown then region:Show() else region:Hide() end
end

local function SetSizeIfChanged(frame, w, h)
    if not frame then return end
    h = h or w
    if frame._msufSISizeW == w and frame._msufSISizeH == h then return end
    frame._msufSISizeW = w
    frame._msufSISizeH = h
    frame:SetSize(w, h)
end

local function SetPointIfChanged(frame, point, relativeTo, relativePoint, x, y)
    if not frame then return end
    x = x or 0
    y = y or 0
    relativePoint = relativePoint or point
    if frame._msufSIAnchorPoint == point
        and frame._msufSIAnchorRel == relativeTo
        and frame._msufSIAnchorRelPoint == relativePoint
        and frame._msufSIAnchorX == x
        and frame._msufSIAnchorY == y
    then
        return
    end
    frame._msufSIAnchorPoint = point
    frame._msufSIAnchorRel = relativeTo
    frame._msufSIAnchorRelPoint = relativePoint
    frame._msufSIAnchorX = x
    frame._msufSIAnchorY = y
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
end

local function SetTextureIfChanged(texRegion, texture)
    if not texRegion then return end
    if texRegion._msufSITexture == texture then return end
    texRegion._msufSITexture = texture
    texRegion:SetTexture(texture)
end

local function SetDesaturatedIfChanged(texRegion, desaturated)
    if not texRegion or not texRegion.SetDesaturated then return end
    desaturated = desaturated and true or false
    if texRegion._msufSIDesaturated == desaturated then return end
    texRegion._msufSIDesaturated = desaturated
    texRegion:SetDesaturated(desaturated)
end

local function SetAlphaIfChanged(region, alpha)
    if not region or not region.SetAlpha then return end
    if region._msufSIAlpha == alpha then return end
    region._msufSIAlpha = alpha
    region:SetAlpha(alpha)
end

local function SetCountTextIfChanged(fs, text)
    if not fs then return end
    if issecretvalue and issecretvalue(text) then
        fs._msufSIText = nil
        fs:SetText(text)
        return
    end
    if fs._msufSIText == text then return end
    fs._msufSIText = text
    fs:SetText(text)
end

local function ClearPlacedText(fs)
    SetCountTextIfChanged(fs, "")
    SetShownIfChanged(fs, false)
end

local function SetCooldownNumbersHidden(cd, hidden)
    if not cd then return end
    hidden = hidden and true or false
    if cd._msufSIHideNumbers == hidden then return end
    cd._msufSIHideNumbers = hidden
    cd:SetHideCountdownNumbers(hidden)
end

local function ClearPlacedCooldown(ind)
    local cd = ind and ind.cooldown
    if not cd then return end
    if cd._msufSICooldownCleared then
        ClearA2CooldownScope(ind)
        return
    end
    cd:Clear()
    cd._msufSICooldownCleared = true
    ClearA2CooldownScope(ind)
end

local function GetPlacedNumberSize(size)
    local fontSize = tonumber(size) or 12
    local width = math_max(18, math_floor(fontSize * 2.2 + 0.5))
    local height = math_max(10, math_floor(fontSize * 1.4 + 0.5))
    return width, height
end

------------------------------------------------------------------------
-- Placed indicator creation
------------------------------------------------------------------------
local function CreatePlacedIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(size, size)
    f:EnableMouse(false)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    f.texture = tex

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetReverse(false)
    cd:SetHideCountdownNumbers(false)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    f.cooldown = cd

    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(cd:GetFrameLevel() + 5)
    local cnt = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cnt:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -1, 1)
    cnt:SetDrawLayer("OVERLAY", 2)
    cnt:SetJustifyH("RIGHT")
    cnt:SetText("")
    cnt:Hide()
    f.count = cnt

    f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0)
    f:SetBackdropBorderColor(0, 0, 0, 0.8)
    f:Hide()
    return f
end

local function CreatePlacedNumber(parent, size)
    local w, h = GetPlacedNumberSize(size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f:EnableMouse(false)

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(false)
    cd:SetReverse(false)
    cd:SetHideCountdownNumbers(false)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    f.cooldown = cd

    local txt = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    txt:SetPoint("CENTER", f, "CENTER", 0, 0)
    txt:SetText("")
    txt:Hide()
    f.previewText = txt

    f:Hide()
    return f
end

local function CreatePlacedSquare(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:EnableMouse(false)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 1, 1, 1)
    f.texture = tex
    f:Hide()
    return f
end

local function CreatePlacedBar(parent, w, h)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:EnableMouse(false)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(1, 1, 1, 0.9)
    f:SetBackdropBorderColor(0, 0, 0, 0.7)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 1, 1, 1)
    f.texture = tex
    f:Hide()
    return f
end

local function GetOrCreatePlaced(f, auraName, itype, size, parent, barWidth, layer)
    f._msufSIPlaced = f._msufSIPlaced or {}
    local ind = f._msufSIPlaced[auraName]
    if not ind or ind._siType ~= itype then
        if ind then
            ClearPlacedCooldown(ind)
            ClearPlacedText(ind.count)
            ClearPlacedText(ind.previewText)
            SetShownIfChanged(ind, false)
        end
        if itype == "bar" then
            ind = CreatePlacedBar(parent, barWidth or (size * 3), size)
        elseif itype == "number" then
            ind = CreatePlacedNumber(parent, size)
        elseif itype == "square" then
            ind = CreatePlacedSquare(parent, size)
        else
            ind = CreatePlacedIcon(parent, size)
        end
        ind._siType = itype
        f._msufSIPlaced[auraName] = ind
    end
    if itype == "bar" then
        SetSizeIfChanged(ind, barWidth or (size * 3), size)
    elseif itype == "number" then
        local w, h = GetPlacedNumberSize(size)
        SetSizeIfChanged(ind, w, h)
    else
        SetSizeIfChanged(ind, size, size)
    end
    if ind:GetParent() ~= parent then
        ind:SetParent(parent)
        ind._msufSIAnchorRel = nil
    end
    if ind.SetFrameLevel then
        local wantLevel
        if GF.SetFrameLayerLevel then
            wantLevel = GF.GetFrameLayerLevel and GF.GetFrameLayerLevel(f, layer, 9)
        elseif parent.GetFrameLevel then
            wantLevel = parent:GetFrameLevel() + (layer or 9)
        end
        if wantLevel and ind._msufSIFrameLevel ~= wantLevel then
            ind._msufSIFrameLevel = wantLevel
            ind:SetFrameLevel(wantLevel)
        end
    end
    return ind
end

------------------------------------------------------------------------
-- Resolve color for a trackable aura
------------------------------------------------------------------------
local function GetAuraColor(specKey, auraName)
    local track = SI.TrackableAuras[specKey]
    if not track then return nil end
    for _, info in ipairs(track) do
        if info.name == auraName then return info.color end
    end
    return nil
end

-- Multi-spec: resolve color from any matching spec
local function GetAuraColorMulti(auraName)
    local sk = _auraSpecMap[auraName]
    if sk then return GetAuraColor(sk, auraName) end
    return nil
end

------------------------------------------------------------------------
-- Apply one placed indicator
------------------------------------------------------------------------
local function ApplyPlaced(f, unit, auraName, cfg, auraData, parent, specKey, isPreview, scale, layer)
    if not cfg or cfg.type == "none" then
        local old = f and f._msufSIPlaced and f._msufSIPlaced[auraName]
        if old then
            ClearPlacedCooldown(old)
            ClearPlacedText(old.count)
            ClearPlacedText(old.previewText)
            SetShownIfChanged(old, false)
        end
        return
    end
    local itype  = cfg.type or "icon"
    local size   = cfg.size or 18
    if scale and scale ~= 1 then
        size = size * scale
        if size < 6 then size = 6 end
    end
    local anchor = cfg.anchor or "TOPLEFT"
    local barWidth = (itype == "bar") and (cfg.barWidth or (size * 3)) or nil
    if barWidth and scale and scale ~= 1 then
        barWidth = barWidth * scale
        if barWidth < 8 then barWidth = 8 end
    end
    local displaySize = size
    local ind = GetOrCreatePlaced(f, auraName, itype, displaySize, parent, barWidth, layer)

    SetPointIfChanged(ind, anchor, parent, anchor, cfg.x or 0, cfg.y or 0)

    if auraData then
        if ind.previewText then
            ClearPlacedText(ind.previewText)
        end

        if itype == "icon" or itype == "number" then
            local sk = _isMultiMode and (_auraSpecMap[auraName] or specKey) or specKey
            local isNumber = (itype == "number")

            if ind.texture then
                if isNumber then
                    SetShownIfChanged(ind.texture, false)
                else
                    SetTextureIfChanged(ind.texture, SI.GetAuraIcon(sk, auraName))
                    SetDesaturatedIfChanged(ind.texture, false)
                    SetAlphaIfChanged(ind.texture, 1)
                    SetShownIfChanged(ind.texture, true)
                end
            end

            if ind.cooldown then
                local aid = auraData.auraInstanceID
                local showCdText = isNumber or cfg.showCooldown ~= false
                ApplyPlacedCooldownStyle(ind.cooldown, f, isNumber)
                SetCooldownNumbersHidden(ind.cooldown, not showCdText)
                if aid and unit and C_UnitAuras and C_UnitAuras.GetAuraDuration then
                    local obj = C_UnitAuras.GetAuraDuration(unit, aid)
                    if obj and ind.cooldown.SetCooldownFromDurationObject then
                        ind.cooldown:SetCooldownFromDurationObject(obj)
                        ind.cooldown._msufSICooldownCleared = nil
                        ClearA2CooldownScope(ind)
                        if showCdText then
                            ApplyPlacedCooldownFont(ind, cfg, isNumber and displaySize or nil)
                        end
                    else
                        ClearPlacedCooldown(ind)
                    end
                else
                    ClearPlacedCooldown(ind)
                end
            end

            if ind.count then
                if isNumber then
                    ClearPlacedText(ind.count)
                else
                    local aid = auraData.auraInstanceID
                    if aid and unit and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
                        local display = C_UnitAuras.GetAuraApplicationDisplayCount(unit, aid, 2, 99)
                        if display ~= nil then
                            SetCountTextIfChanged(ind.count, display)
                            SetShownIfChanged(ind.count, true)
                        else
                            ClearPlacedText(ind.count)
                        end
                    else
                        ClearPlacedText(ind.count)
                    end
                end
            end
        elseif itype == "square" or itype == "bar" then
            local sk = _isMultiMode and (_auraSpecMap[auraName] or specKey) or specKey
            local c = GetAuraColor(sk, auraName) or {0.5, 0.8, 0.5}
            if ind._msufSIColorR ~= c[1] or ind._msufSIColorG ~= c[2]
                or ind._msufSIColorB ~= c[3] or ind._msufSIColorA ~= 1
            then
                ind._msufSIColorR, ind._msufSIColorG, ind._msufSIColorB, ind._msufSIColorA = c[1], c[2], c[3], 1
                ind.texture:SetColorTexture(c[1], c[2], c[3], 1)
            end
        end
        SetShownIfChanged(ind, true)
    elseif cfg.missing then
        if itype == "icon" then
            local sk = _isMultiMode and (_auraSpecMap[auraName] or specKey) or specKey
            SetTextureIfChanged(ind.texture, SI.GetAuraIcon(sk, auraName))
            SetDesaturatedIfChanged(ind.texture, true)
            SetAlphaIfChanged(ind.texture, 0.35)
            SetShownIfChanged(ind.texture, true)
            ClearPlacedCooldown(ind)
            ClearPlacedText(ind.count)
            ClearPlacedText(ind.previewText)
        elseif itype == "number" then
            if ind.cooldown then
                ApplyPlacedCooldownStyle(ind.cooldown, f, true)
                ClearPlacedCooldown(ind)
                SetCooldownNumbersHidden(ind.cooldown, false)
            end
            if ind.previewText then
                ApplyPreviewTextStyle(ind.previewText, cfg, displaySize, true)
                SetCountTextIfChanged(ind.previewText, isPreview and "9" or "0")
                SetShownIfChanged(ind.previewText, true)
            end
        elseif itype == "square" or itype == "bar" then
            if ind._msufSIColorR ~= 0.3 or ind._msufSIColorG ~= 0.3
                or ind._msufSIColorB ~= 0.3 or ind._msufSIColorA ~= 0.5
            then
                ind._msufSIColorR, ind._msufSIColorG, ind._msufSIColorB, ind._msufSIColorA = 0.3, 0.3, 0.3, 0.5
                ind.texture:SetColorTexture(0.3, 0.3, 0.3, 0.5)
            end
        end
        SetShownIfChanged(ind, true)
    else
        ClearPlacedCooldown(ind)
        ClearPlacedText(ind.count)
        ClearPlacedText(ind.previewText)
        SetShownIfChanged(ind, false)
    end

    -- Highlight: yellow pulsing border when this SI is selected in the editor
    local GF = ns.GF
    local isHL = GF and GF._highlightedSI == auraName
    if isHL and ind:IsShown() then
        if not ind._msufSIHighlight then
            local hl = CreateFrame("Frame", nil, ind, "BackdropTemplate")
            hl:SetPoint("TOPLEFT", ind, "TOPLEFT", -2, 2)
            hl:SetPoint("BOTTOMRIGHT", ind, "BOTTOMRIGHT", 2, -2)
            hl:SetFrameLevel(ind:GetFrameLevel() + 10)
            hl:EnableMouse(false)
            hl:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
            hl:SetBackdropColor(0, 0, 0, 0)
            hl:SetBackdropBorderColor(1, 0.82, 0, 1)
            local ag = hl:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local anim = ag:CreateAnimation("Alpha")
            anim:SetFromAlpha(1.0)
            anim:SetToAlpha(0.25)
            anim:SetDuration(0.5)
            anim:SetSmoothing("IN_OUT")
            hl._animGroup = ag
            ind._msufSIHighlight = hl
        end
        SetShownIfChanged(ind._msufSIHighlight, true)
        if ind._msufSIHighlight._animGroup then ind._msufSIHighlight._animGroup:Play() end
    elseif ind._msufSIHighlight then
        if ind._msufSIHighlight._animGroup then ind._msufSIHighlight._animGroup:Stop() end
        SetShownIfChanged(ind._msufSIHighlight, false)
    end
end

------------------------------------------------------------------------
-- Frame-level effects
------------------------------------------------------------------------
local function EnsureHealthTint(f)
    if f._msufSIHealthTint then return f._msufSIHealthTint end
    local bar = f.health
    if not bar then return nil end
    local tex = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    tex:SetAllPoints(bar)
    tex:SetBlendMode("ADD")
    tex:SetColorTexture(1, 1, 1, 0.15)
    tex:Hide()
    f._msufSIHealthTint = tex
    return tex
end

local function EnsureBorderOverlay(f)
    if f._msufSIBorderOverlay then return f._msufSIBorderOverlay end
    local anchor = f.barGroup or f
    local overlay = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    overlay:SetAllPoints(anchor)
    overlay:SetFrameLevel(anchor:GetFrameLevel() + 8)
    overlay:EnableMouse(false)
    overlay:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    overlay:SetBackdropColor(0, 0, 0, 0)
    overlay:Hide()
    f._msufSIBorderOverlay = overlay
    return overlay
end

------------------------------------------------------------------------
-- Glow effect: animated pulsing border (C-side AnimationGroup, zero Lua)
------------------------------------------------------------------------
local function EnsureGlowOverlay(f)
    if f._msufSIGlow then return f._msufSIGlow end
    local anchor = f.barGroup or f
    local glow = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 2, -2)
    glow:SetFrameLevel(anchor:GetFrameLevel() + 9)
    glow:EnableMouse(false)
    glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 3 })
    glow:SetBackdropColor(0, 0, 0, 0)
    glow:SetBackdropBorderColor(1, 1, 1, 0.8)

    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(1.0)
    anim:SetToAlpha(0.25)
    anim:SetDuration(0.7)
    anim:SetSmoothing("IN_OUT")
    glow._animGroup = ag

    glow:Hide()
    f._msufSIGlow = glow
    return glow
end

------------------------------------------------------------------------
-- Pulse effect: animated health bar overlay (C-side AnimationGroup)
------------------------------------------------------------------------
local function EnsurePulseOverlay(f)
    if f._msufSIPulse then return f._msufSIPulse end
    local bar = f.health
    if not bar then return nil end
    local pulse = CreateFrame("Frame", nil, bar)
    pulse:SetAllPoints(bar)
    pulse:SetFrameLevel(bar:GetFrameLevel() + 2)
    pulse:EnableMouse(false)
    local tex = pulse:CreateTexture(nil, "OVERLAY", nil, 2)
    tex:SetAllPoints()
    tex:SetBlendMode("ADD")
    tex:SetColorTexture(1, 1, 1, 0.25)
    pulse._tex = tex

    local ag = pulse:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(1.0)
    anim:SetToAlpha(0.1)
    anim:SetDuration(0.5)
    anim:SetSmoothing("IN_OUT")
    pulse._animGroup = ag

    pulse:Hide()
    f._msufSIPulse = pulse
    return pulse
end

------------------------------------------------------------------------
-- Reset / Apply frame effects
------------------------------------------------------------------------
local function ResetFrameEffects(f)
    -- Clear health bar color override â†’ restore normal health color
    local hadHealthTint = f._msufSIHealthColorR
    f._msufSIHealthColorR = nil
    f._msufSIHealthColorG = nil
    f._msufSIHealthColorB = nil
    f._msufSIHealthAppliedR = nil
    f._msufSIHealthAppliedG = nil
    f._msufSIHealthAppliedB = nil
    if hadHealthTint then
        -- Invalidate diff-gate stamp so ApplyHealthColor re-applies unconditionally
        f._msufGFHCStamp = nil
        if GF._ApplyHealthColor and f.health and f.unit then
            GF._ApplyHealthColor(f, f._msufGFKind or "party", f.unit)
        end
    end
    -- Legacy tint overlay (hide if still exists from old config)
    if f._msufSIHealthTint then f._msufSIHealthTint:Hide() end
    if f._msufSIBorderOverlay then f._msufSIBorderOverlay:Hide() end
    if f._msufSIGlow then
        if f._msufSIGlow._animGroup then f._msufSIGlow._animGroup:Stop() end
        f._msufSIGlow:Hide()
    end
    if f._msufSIPulse then
        if f._msufSIPulse._animGroup then f._msufSIPulse._animGroup:Stop() end
        f._msufSIPulse:Hide()
    end
    if f._msufSINameColorActive and f.nameText then
        f._msufSINameColorActive = nil
        f._msufSINameColorR = nil
        f._msufSINameColorG = nil
        f._msufSINameColorB = nil
        f._msufSINameColorA = nil
        -- Restore configured name color (CLASS/CUSTOM/DEFAULT â€” not hardcoded white)
        local kind = f._msufGFKind or "party"
        local unit = f.unit
        local classToken
        if unit and UnitClass then
            local _, ct = UnitClass(unit)
            classToken = ct
        end
        if GF.ResolveNameColor then
            local nr, ng, nb = GF.ResolveNameColor(kind, classToken)
            f.nameText:SetTextColor(nr or 1, ng or 1, nb or 1, 1)
        else
            local fr, fg, fb = GF.ResolveFontColor(kind)
            f.nameText:SetTextColor(fr or 1, fg or 1, fb or 1, 1)
        end
    end
end

local function ApplyFrameEffect(f, auraName, cfg, auraData)
    if not cfg or not cfg.type or not auraData then return end
    local c = cfg.color or _defaultFrameColor

    if cfg.type == "healthtint" then
        -- Full bar color override (not a tint overlay)
        -- Sets _msufSIHealthColorR/G/B on frame â†’ ApplyHealthColor in Effects respects it
        if f.health then
            f._msufSIHealthColorR = c[1]
            f._msufSIHealthColorG = c[2]
            f._msufSIHealthColorB = c[3]
            if f._msufSIHealthAppliedR ~= c[1] or f._msufSIHealthAppliedG ~= c[2]
                or f._msufSIHealthAppliedB ~= c[3]
            then
                f._msufSIHealthAppliedR, f._msufSIHealthAppliedG, f._msufSIHealthAppliedB = c[1], c[2], c[3]
                f.health:SetStatusBarColor(c[1], c[2], c[3], 1)
            end
            if GF.ApplyHealthBarAlpha then
                GF.ApplyHealthBarAlpha(f, f._msufGFKind or "party")
            end
        end
    elseif cfg.type == "border" then
        local overlay = EnsureBorderOverlay(f)
        if overlay then
            local thickness = cfg.thickness or 2
            local curThick = overlay._msufThickness
            if curThick ~= thickness then
                overlay:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = thickness })
                overlay:SetBackdropColor(0, 0, 0, 0)
                overlay._msufThickness = thickness
            end
            local a = c[4] or 1
            if overlay._msufSIColorR ~= c[1] or overlay._msufSIColorG ~= c[2]
                or overlay._msufSIColorB ~= c[3] or overlay._msufSIColorA ~= a
            then
                overlay._msufSIColorR, overlay._msufSIColorG, overlay._msufSIColorB, overlay._msufSIColorA = c[1], c[2], c[3], a
                overlay:SetBackdropBorderColor(c[1], c[2], c[3], a)
            end
            SetShownIfChanged(overlay, true)
        end
    elseif cfg.type == "glow" then
        local glow = EnsureGlowOverlay(f)
        if glow then
            local thickness = cfg.thickness or 3
            local curThick = glow._msufThickness
            if curThick ~= thickness then
                glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = thickness })
                glow:SetBackdropColor(0, 0, 0, 0)
                glow._msufThickness = thickness
            end
            local anchor = f.barGroup or f
            if glow._msufSIAnchorRel ~= anchor or glow._msufSIAnchorX ~= thickness then
                glow._msufSIAnchorRel = anchor
                glow._msufSIAnchorX = thickness
                glow:ClearAllPoints()
                glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", -thickness, thickness)
                glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", thickness, -thickness)
            end
            local a = c[4] or 0.9
            if glow._msufSIColorR ~= c[1] or glow._msufSIColorG ~= c[2]
                or glow._msufSIColorB ~= c[3] or glow._msufSIColorA ~= a
            then
                glow._msufSIColorR, glow._msufSIColorG, glow._msufSIColorB, glow._msufSIColorA = c[1], c[2], c[3], a
                glow:SetBackdropBorderColor(c[1], c[2], c[3], a)
            end
            SetAlphaIfChanged(glow, 1)
            SetShownIfChanged(glow, true)
            if glow._animGroup and not glow._animGroup:IsPlaying() then
                glow._animGroup:Play()
            end
        end
    elseif cfg.type == "pulse" then
        local pulse = EnsurePulseOverlay(f)
        if pulse then
            local a = cfg.alpha or c[4] or 0.25
            if pulse._msufSIColorR ~= c[1] or pulse._msufSIColorG ~= c[2]
                or pulse._msufSIColorB ~= c[3] or pulse._msufSIColorA ~= a
            then
                pulse._msufSIColorR, pulse._msufSIColorG, pulse._msufSIColorB, pulse._msufSIColorA = c[1], c[2], c[3], a
                pulse._tex:SetColorTexture(c[1], c[2], c[3], a)
            end
            SetAlphaIfChanged(pulse, 1)
            SetShownIfChanged(pulse, true)
            if pulse._animGroup and not pulse._animGroup:IsPlaying() then
                pulse._animGroup:Play()
            end
        end
    elseif cfg.type == "namecolor" then
        if f.nameText then
            f._msufSINameColorActive = auraName
            local a = c[4] or 1
            if f._msufSINameColorR ~= c[1] or f._msufSINameColorG ~= c[2]
                or f._msufSINameColorB ~= c[3] or f._msufSINameColorA ~= a
            then
                f._msufSINameColorR, f._msufSINameColorG, f._msufSINameColorB, f._msufSINameColorA = c[1], c[2], c[3], a
                f.nameText:SetTextColor(c[1], c[2], c[3], a)
            end
        end
    end
end

local function ApplyBestFrameEffects(f, bestByType)
    for i = 1, #_siBestTypes do
        local fx = bestByType[_siBestTypes[i]]
        if fx then ApplyFrameEffect(f, fx.name, fx.cfg, fx.data) end
    end
end

------------------------------------------------------------------------
-- Multi-spec dedup buffer (pre-allocated)
------------------------------------------------------------------------
local _multiProcessed = {}

local function ClearBestByType(bestByType)
    for i = 1, #_siBestTypes do
        local ft = _siBestTypes[i]
        local slot = _siBestSlots[ft]
        slot.name, slot.cfg, slot.data, slot.prio = nil, nil, nil, nil
        bestByType[ft] = nil
    end
end

local function StoreBestFrameEffect(bestByType, ft, auraName, cfg, auraData, prio)
    local slot = _siBestSlots[ft]
    if not slot then return end

    local best = bestByType[ft]
    if best and prio >= best.prio then return end

    slot.name = auraName
    slot.cfg = cfg
    slot.data = auraData
    slot.prio = prio
    bestByType[ft] = slot
end

------------------------------------------------------------------------
-- Core update iteration (shared logic for single/multi)
------------------------------------------------------------------------
local function IterateSpecConfig(f, unit, specKey, specList, specCount, parent, scale, bestByType, dedup, processed, siLayer)
    for i = 1, specCount do
        local item = specList[i]
        local auraName, auraCfg = item.name, item.cfg
        if auraCfg and auraCfg.enabled ~= false then
            if not processed or not processed[auraName] then
                if processed then processed[auraName] = true end
                local auraData = _scanResults[auraName]
                if auraCfg.placed then
                    ApplyPlaced(f, unit, auraName, auraCfg.placed, auraData, parent, specKey, false, scale, siLayer)
                end
                if auraData and auraData.auraInstanceID and (auraCfg.placed or auraCfg.frame) then
                    dedup[auraData.auraInstanceID] = true
                    if auraCfg.placed then
                        local ptype = auraCfg.placed.type
                        if ptype == nil or ptype == "icon" then
                            f._msufSIHasIconPlaced = true
                        end
                    end
                end
                if auraCfg.frame and auraCfg.frame.type and auraData then
                    local ft = auraCfg.frame.type
                    local prio = auraCfg.frame.priority or 5
                    StoreBestFrameEffect(bestByType, ft, auraName, auraCfg.frame, auraData, prio)
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Main update
------------------------------------------------------------------------
function GF.UpdateSpellIndicators(f, unit)
    if not f or not unit then return end
    if not UnitExists(unit) then GF.HideSpellIndicators(f); return end

    local kind  = f._msufGFKind or "party"
    local siCfg = GetSIConfig(kind)
    if not siCfg or not siCfg.enabled then GF.HideSpellIndicators(f); return end

    local specKey = ResolveRuntimeSpec(siCfg)
    if not specKey then GF.HideSpellIndicators(f); return end

    CompileLookup(specKey, siCfg)

    local parent = f.barGroup or f
    local scale = GF.GetDynamicScale and GF.GetDynamicScale(GF.GetConf(kind)) or 1

    ScanUnit(unit, kind, siCfg, specKey)
    ResetFrameEffects(f)

    if not f._msufSIDedupIDs then f._msufSIDedupIDs = {} end
    local dedup = f._msufSIDedupIDs
    for k in pairs(dedup) do dedup[k] = nil end
    f._msufSIHasIconPlaced = false

    -- Reuse module-level table (cleared per call, zero GC)
    local bestByType = _siBestByType
    ClearBestByType(bestByType)
    local siLayer = siCfg.layer or 9

    if specKey == "multi" then
        for k in pairs(_multiProcessed) do _multiProcessed[k] = nil end
        local specs, specCount = GetMultiSpecList(siCfg)
        if specs then
            for si = 1, specCount do
                local sk = specs[si]
                local specList, auraCount = GetSpecConfigList(siCfg, sk)
                if specList then
                    IterateSpecConfig(f, unit, sk, specList, auraCount, parent, scale, bestByType, dedup, _multiProcessed, siLayer)
                end
            end
        end
    else
        local specList, auraCount = GetSpecConfigList(siCfg, specKey)
        if not specList then GF.HideSpellIndicators(f); return end
        IterateSpecConfig(f, unit, specKey, specList, auraCount, parent, scale, bestByType, dedup, nil, siLayer)
    end

    ApplyBestFrameEffects(f, bestByType)

    if f._msufSIPlaced then
        for auraName, ind in pairs(f._msufSIPlaced) do
            local enabled = false
            if specKey == "multi" then
                local specs, specCount = GetMultiSpecList(siCfg)
                if specs then
                    for si = 1, specCount do
                        local sk = specs[si]
                        local sc = siCfg.specs and siCfg.specs[sk]
                        local ac = sc and sc[auraName]
                        if ac and ac.enabled ~= false and ac.placed then enabled = true; break end
                    end
                end
            else
                local sc = siCfg.specs and siCfg.specs[specKey]
                local ac = sc and sc[auraName]
                if ac and ac.enabled ~= false and ac.placed then enabled = true end
            end
            if not enabled then
                ClearPlacedCooldown(ind)
                ClearPlacedText(ind.count)
                ClearPlacedText(ind.previewText)
                SetShownIfChanged(ind, false)
            end
        end
    end
end

function GF.HideSpellIndicators(f)
    if f._msufSIPlaced then
        for _, ind in pairs(f._msufSIPlaced) do
            ClearPlacedCooldown(ind)
            ClearPlacedText(ind.count)
            ClearPlacedText(ind.previewText)
            SetShownIfChanged(ind, false)
        end
    end
    if f._msufSIDedupIDs then
        for k in pairs(f._msufSIDedupIDs) do f._msufSIDedupIDs[k] = nil end
    end
    f._msufSIHasIconPlaced = false
    ResetFrameEffects(f)
end

------------------------------------------------------------------------
-- Preview
------------------------------------------------------------------------
function GF.PreviewSpellIndicators(f, kind, classToken, specIdx)
    local siCfg = GetSIConfig(kind)
    if not siCfg or not siCfg.enabled then GF.HideSpellIndicators(f); return end
    local specKey
    if (siCfg.spec or "auto") == "multi" then
        specKey = "multi"
    elseif classToken and specIdx then
        specKey = SI.SpecMap[classToken .. "_" .. specIdx]
    else
        specKey = ResolveSpec(siCfg)
    end
    if not specKey then GF.HideSpellIndicators(f); return end

    CompileLookup(specKey, siCfg)

    local parent = f.barGroup or f
    ResetFrameEffects(f)
    if f._msufSIPlaced then
        for _, ind in pairs(f._msufSIPlaced) do ind:Hide() end
    end
    local siLayer = siCfg.layer or 9

    local function PreviewSpecConfig(sk, specCfg, processed, bestByType)
        local function PreviewAura(auraName, auraCfg)
            if not auraCfg or auraCfg.enabled == false then return end
            if processed then
                if processed[auraName] then return end
                processed[auraName] = true
            end
            local mock = { icon = SI.GetAuraIcon(sk, auraName), auraInstanceID = nil, applications = 0 }
            if auraCfg.placed then ApplyPlaced(f, nil, auraName, auraCfg.placed, mock, parent, sk, true, nil, siLayer) end
            if auraCfg.frame and auraCfg.frame.type then
                local ft = auraCfg.frame.type
                local prio = auraCfg.frame.priority or 5
                local best = bestByType[ft]
                if not best or prio < best.prio then
                    bestByType[ft] = { name = auraName, cfg = auraCfg.frame, data = mock, prio = prio }
                end
            end
        end

        local trackable = SI.TrackableAuras and SI.TrackableAuras[sk]
        if trackable then
            for _, info in ipairs(trackable) do
                PreviewAura(info.name, specCfg[info.name])
            end
        end
        for auraName, auraCfg in pairs(specCfg) do
            PreviewAura(auraName, auraCfg)
        end
    end

    if specKey == "multi" then
        local ms = siCfg.multiSpecs
        if not ms then return end
        local bestByType = {}
        for k in pairs(_multiProcessed) do _multiProcessed[k] = nil end
        for sk in pairs(ms) do
            local specCfg = EnsureSpecConfig(siCfg, sk)
            if specCfg then
                PreviewSpecConfig(sk, specCfg, _multiProcessed, bestByType)
            end
        end
        for _, fx in pairs(bestByType) do ApplyFrameEffect(f, fx.name, fx.cfg, fx.data) end
        return
    end

    local specCfg = EnsureSpecConfig(siCfg, specKey)
    if not specCfg then return end

    local bestByType = {}
    PreviewSpecConfig(specKey, specCfg, nil, bestByType)
    for _, fx in pairs(bestByType) do
        ApplyFrameEffect(f, fx.name, fx.cfg, fx.data)
    end
end

------------------------------------------------------------------------
-- Import / Export helpers
------------------------------------------------------------------------
do
    local function SerializeValue(v)
        local vt = type(v)
        if vt == "string" then return string.format("%q", v) end
        if vt == "number" then return tostring(v) end
        if vt == "boolean" then return v and "true" or "false" end
        if vt ~= "table" then return "nil" end
        local parts = {}
        for key, val in pairs(v) do
            local ks
            local kt = type(key)
            if kt == "string" then
                ks = "[" .. string.format("%q", key) .. "]"
            elseif kt == "number" then
                ks = "[" .. key .. "]"
            end
            if ks then parts[#parts + 1] = ks .. "=" .. SerializeValue(val) end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end

    function SI.ExportConfig(siCfg, specKey)
        if not siCfg or not specKey then return nil end
        local data = {}
        if siCfg.specs and siCfg.specs[specKey] then
            data.specs = siCfg.specs[specKey]
        end
        if siCfg.sortOrder and siCfg.sortOrder[specKey] then
            data.sortOrder = siCfg.sortOrder[specKey]
        end
        data.specKey = specKey
        return SerializeValue(data)
    end

    function SI.ImportConfig(siCfg, str)
        if not siCfg or not str or str == "" then return false end
        local fn = loadstring("return " .. str)
        if not fn then return false end
        setfenv(fn, {})
        local ok, data = pcall(fn)
        if not ok or type(data) ~= "table" then return false end
        local sk = data.specKey
        if not sk or type(sk) ~= "string" then return false end
        if not SI.SpecInfo[sk] then return false end
        siCfg.specs = siCfg.specs or {}
        if data.specs and type(data.specs) == "table" then
            siCfg.specs[sk] = data.specs
        end
        siCfg.sortOrder = siCfg.sortOrder or {}
        if data.sortOrder and type(data.sortOrder) == "table" then
            siCfg.sortOrder[sk] = data.sortOrder
        end
        return true, sk
    end
end

------------------------------------------------------------------------
-- Default factories + migration
------------------------------------------------------------------------
do
local function MakeBuffDefaults()
    return {
        enabled = true, anchor = "BOTTOMRIGHT", growth = "LEFTUP",
        x = 0, y = 0, size = 22, perRow = 4, max = 6, spacing = 1,
        layer = 5,
        filterMode = "RAID_PLAYER",
        showCooldownSwipe = true,
        showCooldown = true, cooldownAnchor = "CENTER",
        cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 8, cooldownOutline = "OUTLINE",
        showStacks = true, stackAnchor = "BOTTOMRIGHT",
        stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
    }
end
local function MakeDebuffDefaults()
    return {
        enabled = true, anchor = "TOPLEFT", growth = "RIGHTDOWN",
        x = 0, y = 0, size = 20, perRow = 3, max = 6, spacing = 1,
        layer = 6,
        showDispelBorder = true,
        showCooldownSwipe = true,
        showCooldown = true, cooldownAnchor = "CENTER",
        cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 8, cooldownOutline = "OUTLINE",
        showStacks = true, stackAnchor = "BOTTOMRIGHT",
        stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
    }
end
local function MakeExternalsDefaults()
    return {
        enabled = true, anchor = "CENTER", growth = "RIGHTDOWN",
        x = 0, y = 0, size = 28, perRow = 3, max = 2, spacing = 1,
        layer = 7,
        showCooldownSwipe = true,
        showCooldown = true, cooldownAnchor = "CENTER",
        cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 10, cooldownOutline = "OUTLINE",
        showStacks = false, stackAnchor = "BOTTOMRIGHT",
        stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
    }
end
local function MakePrivateAuraDefaults()
    return {
        enabled = true, max = 4, size = 20, anchor = "TOPRIGHT",
        direction = "LEFT", spacing = 1, x = 0, y = 0,
        layer = 8,
        showCountdown = true, showNumbers = false,
        showDispelType = false, showDuration = false,
        durationAnchor = "BOTTOM", durationOffsetX = 0, durationOffsetY = -1,
    }
end

local function EnsureAuraGroupDefaults(group, defaults)
    if type(group) ~= "table" or type(defaults) ~= "table" then return end
    for key, value in pairs(defaults) do
        if group[key] == nil then group[key] = value end
    end
end

local function EnsureBlizzardAuraDefaults(auras)
    if type(auras) ~= "table" then return end
    if auras.dynamicScale == nil then auras.dynamicScale = false end
    if auras.showTooltip == nil then auras.showTooltip = true end
    if auras.sortByDuration == nil then auras.sortByDuration = false end
    if auras.preferPlayer == nil then auras.preferPlayer = true end
    if auras.renderer == nil then auras.renderer = "BLIZZARD" end
    if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
    local types = auras.blizzardTypes
    if types.buffs == nil then types.buffs = true end
    if types.debuffs == nil then types.debuffs = true end
    if types.dispels == nil then types.dispels = true end
    if types.externals == nil then types.externals = true end
    if types.privateAuras == nil then types.privateAuras = true end
    if auras.blizzardIconSize == nil then auras.blizzardIconSize = 20 end
    if auras.blizzardShowCooldownText == nil then auras.blizzardShowCooldownText = true end
    if auras.blizzardOrganizationType == nil then auras.blizzardOrganizationType = "default" end
    if auras.blizzardDispelMode == nil then auras.blizzardDispelMode = "allDispellable" end
    if auras.blizzardContainerStrata == nil then auras.blizzardContainerStrata = "AUTO" end
    if auras.blizzardContainerFrameLevel == nil then auras.blizzardContainerFrameLevel = 1 end
    if auras.blizzardPrivateLayerFix == nil then auras.blizzardPrivateLayerFix = true end
    if auras.blizzardPrivateLayerOffset == nil then auras.blizzardPrivateLayerOffset = 1 end
    auras.blizzardContainerAnchor = "FRAME"
    auras.blizzardContainerX = 0
    auras.blizzardContainerY = 0
end

function GF.MigrateAuraConfig(conf, isRaid)
    if not conf then return end
    if conf.aurasEnabled ~= nil and not conf.auras then
        local b = MakeBuffDefaults()
        b.enabled = conf.aurasEnabled ~= false
        b.anchor = conf.auraAnchor or "BOTTOMLEFT"
        b.size = conf.auraIconSize or 20
        b.perRow = conf.auraPerRow or (conf.auraMaxIcons or 4)
        b.max = conf.auraMaxIcons or 4
        b.spacing = conf.auraSpacing or 1
        local d = MakeDebuffDefaults()
        d.size = conf.auraIconSize or 20
        d.max = conf.auraMaxIcons or 4
        d.spacing = conf.auraSpacing or 1
        conf.auras = { enabled = conf.aurasEnabled, buff = b, debuff = d, externals = MakeExternalsDefaults() }
        conf.aurasEnabled = nil; conf.auraMaxIcons = nil; conf.auraIconSize = nil
        conf.auraAnchor = nil; conf.auraGrowthX = nil; conf.auraGrowthY = nil
        conf.auraSpacing = nil; conf.auraPerRow = nil
    end
    if not conf.auras then
        local b = MakeBuffDefaults(); local d = MakeDebuffDefaults(); local e = MakeExternalsDefaults()
        if isRaid then
            b.size = 16; b.max = 3; b.perRow = 3
            d.size = 14; d.max = 3; d.perRow = 3
            e.size = 24; e.max = 2; e.perRow = 2
        end
        conf.auras = { enabled = true, buff = b, debuff = d, externals = e }
    end
    if conf.privateAurasEnabled ~= nil and not conf.privateAuras then
        conf.privateAuras = {
            enabled = conf.privateAurasEnabled,
            max = conf.privateAuraMax or 4, size = conf.privateAuraSize or 20,
            anchor = conf.privateAuraAnchor or "TOPRIGHT",
            direction = "LEFT", spacing = 1,
            x = conf.privateAuraX or 0, y = conf.privateAuraY or 0,
            showCountdown = conf.privateAuraCountdown ~= false,
            showNumbers = false, showDispelType = false, showDuration = false,
            durationAnchor = "BOTTOM", durationOffsetX = 0, durationOffsetY = -1,
        }
        conf.privateAurasEnabled = nil; conf.privateAuraMax = nil
        conf.privateAuraSize = nil; conf.privateAuraAnchor = nil
        conf.privateAuraX = nil; conf.privateAuraY = nil; conf.privateAuraCountdown = nil
    end
    if not conf.privateAuras then conf.privateAuras = MakePrivateAuraDefaults() end
    EnsureBlizzardAuraDefaults(conf.auras)
    if type(conf.auras.buff) ~= "table" then conf.auras.buff = MakeBuffDefaults() end
    if type(conf.auras.debuff) ~= "table" then conf.auras.debuff = MakeDebuffDefaults() end
    if type(conf.auras.externals) ~= "table" then conf.auras.externals = MakeExternalsDefaults() end
    EnsureAuraGroupDefaults(conf.auras.buff, MakeBuffDefaults())
    EnsureAuraGroupDefaults(conf.auras.debuff, MakeDebuffDefaults())
    EnsureAuraGroupDefaults(conf.auras.externals, MakeExternalsDefaults())
    if not conf.spellIndicators then conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9 } end
end
end -- do block

------------------------------------------------------------------------
_G.MSUF_GF_UpdateSpellIndicators  = GF.UpdateSpellIndicators
_G.MSUF_GF_HideSpellIndicators   = GF.HideSpellIndicators
_G.MSUF_GF_PreviewSpellIndicators = GF.PreviewSpellIndicators
_G.MSUF_GF_MigrateAuraConfig     = GF.MigrateAuraConfig
