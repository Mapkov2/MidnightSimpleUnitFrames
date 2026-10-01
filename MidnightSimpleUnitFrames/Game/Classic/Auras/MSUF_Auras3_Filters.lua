--- Game/Classic/Auras/MSUF_Auras3_Filters.lua
--- Which auras a lane shows on Classic: filter-token membership (cached per
--- unit and filter), "cast by me" ownership, the blacklist, Hide permanent,
--- the sated rule, custom-container matching (Features.lua) and the lane's
--- harmful or helpful side, plus the dispel-trigger match the frame visuals
--- share. Nothing here touches a widget.
---
--- Game/<Flavor>/Auras.xml loads the unit-frame aura backend after Compile.lua
--- in this order: Buttons, Filters, FrameVisuals, Lanes, UnitFrames, Requests.
--- Each file imports the earlier ones from A3._ClassicBackend at load time.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local A3 = MSUF.MSUF_Auras3
local Backend = type(A3) == "table" and A3._ClassicBackend
if not Backend or Backend.Filters then return end
local Compile, Buttons = A3._ClassicCompile, Backend.Buttons
local Filters = {}

local type, tonumber = type, tonumber
local math_floor = math.floor
local UnitIsUnit = _G.UnitIsUnit
local UnitIsPlayer = _G.UnitIsPlayer
local UnitPlayerOrPetInParty = _G.UnitPlayerOrPetInParty
local UnitPlayerOrPetInRaid = _G.UnitPlayerOrPetInRaid
local IsSecret = _G.issecretvalue or function() return false end
local C_UnitAuras = _G.C_UnitAuras
local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot

local WipeTable = Compile.WipeTable
local FillAuraSlots = Compile.FillAuraSlots
local PlainNumber = Compile.PlainNumber
local PlainString = Compile.PlainString
local RemainingTime = Buttons.RemainingTime
-- Features.lua loads before this file; ShouldShowAura falls back to the live
-- field only if a harness loads the backend without it.
local Features = A3.ClassicFeatures

-- Intentional cross-client data kept in step with the Retail list: an ID that
-- this Classic client never applies simply never matches, so no per-flavor split.
local SATED_SPELLS = {
    [57723] = true, -- Exhaustion
    [57724] = true, -- Sated
    [80354] = true, -- Temporal Displacement
    [95809] = true, -- Insanity
    [160455] = true, -- Fatigued
    [264689] = true, -- Fatigued
}

--- Token-filter membership. C_UnitAuras.IsAuraFilteredOutByInstanceID has no
--- engine-validated consumer on any Classic branch and reported every aura as
--- filtered on Mists, which turned each token filter into an empty lane.
--- Blizzard's own Classic UI evaluates filter tokens through aura scans
--- (Blizzard_RaidUI walks "HELPFUL|RAID|PLAYER"), so membership is derived
--- from the same scan primitive: one filtered instance-ID scan per
--- unit+filter, cached until the unit's serial is bumped.
--- UpdateAuras bumps the serial only when membership can change: a full update
--- (forced, no payload, isFullUpdate, a pending needFullUpdate, or a newly
--- applied config) or a payload with added or removed auras. An update-only
--- payload refreshes existing auras and keeps each aura's source, so it keeps
--- the cached sets; a set built at an older serial is rebuilt lazily on its
--- next query.
--- (Lane config compilation lives in Game/Classic/Auras/MSUF_Auras3_Compile.lua.)
--- Sets are stored as sets[unit][filter] rather than under a concatenated
--- "unit|filter" key: both levels are bounded by the finite unit tokens and
--- lane filter strings, so a cached membership query allocates nothing.
local TokenSets, TokenSerial = {}, {}
--- Per filter: true once C_UnitAuras.GetUnitAuraInstanceIDs agreed with the
--- slot walk on a non-empty set, false once it disagreed (walk for the rest of
--- the session), nil while unverified.
local TokenTrust = {}
local function TokenSet(unit, filter)
    local serial = TokenSerial[unit] or 0
    local setsByFilter = TokenSets[unit]
    if not setsByFilter then
        setsByFilter = {}
        TokenSets[unit] = setsByFilter
    end
    local entry = setsByFilter[filter]
    if entry and entry.serial == serial then return entry.set end
    if not entry then
        entry = { set = {} }
        setsByFilter[filter] = entry
    end
    local set = WipeTable(entry.set)
    entry.set = set
    entry.serial = serial
    -- One C_UnitAuras.GetUnitAuraInstanceIDs call (documented on every
    -- Classic branch) answers a rebuild without an AuraData per aura. No
    -- Blizzard Classic UI calls it, so each filter first checks it against
    -- the GetAuraSlots/GetAuraDataBySlot walk AuraUtil.ForEachAura uses: the
    -- first non-empty agreement trusts it, any disagreement keeps the walk.
    local trust = TokenTrust[filter]
    local getIDs = trust ~= false and C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs
    local ids = type(getIDs) == "function" and getIDs(unit, filter) or nil
    if type(ids) ~= "table" or IsSecret(ids) then ids = nil end
    if ids and (trust == true or not (GetAuraSlots and GetAuraDataBySlot)) then
        for i = 1, #ids do
            local id = ids[i]
            if id ~= nil and not IsSecret(id) then set[id] = true end
        end
        return set
    end
    if GetAuraSlots and GetAuraDataBySlot then
        local slots, count = FillAuraSlots(entry.scratch or {}, GetAuraSlots(unit, filter))
        entry.scratch = slots
        local walked = 0
        for i = 2, count do
            local data = GetAuraDataBySlot(unit, slots[i])
            local id = data and data.auraInstanceID
            if id ~= nil and not IsSecret(id) and set[id] == nil then
                set[id] = true
                walked = walked + 1
            end
        end
        if ids then
            local agree = #ids == walked
            for i = 1, #ids do
                if not agree then break end
                local id = ids[i]
                agree = id ~= nil and not IsSecret(id) and set[id] == true
            end
            if not agree then
                TokenTrust[filter] = false
            elseif walked > 0 then
                TokenTrust[filter] = true
            end
        end
    end
    return set
end

local function Filtered(unit, auraInstanceID, filter)
    if unit == nil or auraInstanceID == nil or filter == nil then return false end
    return TokenSet(unit, filter)[auraInstanceID] ~= true
end

local function ProcessData(lane, unit, data, fromLaneScan)
    if type(data) ~= "table" then return nil end
    local auraInstanceID = data.auraInstanceID
    if auraInstanceID == nil then return nil end
    local cfg = lane.config
    if cfg.nativePlayerFilter == true
        and lane._msufA3NativePlayerFilterTrusted ~= false then
        -- Full-scan data already passed Blizzard's PLAYER filter. Delta
        -- payloads do not carry that guarantee, so test their exact native
        -- membership before they can enter or remain in an Only Mine lane.
        lane.mine[auraInstanceID] = fromLaneScan == true
            or not Filtered(unit, auraInstanceID, cfg.filter)
        return data
    end
    if cfg.needsPlayerFlag == true then
        -- Mists/TBC do not reliably populate isFromPlayerOrPlayerPet (the
        -- player's own party-frame HoTs carried false/nil, which blanked
        -- "only mine" lanes). Blizzard compares sourceUnit through UnitIsUnit,
        -- because the player or pet can arrive through an equivalent group /
        -- vehicle token. A positive legacy flag is still useful, but false is
        -- not authoritative. Fall back to PLAYER scan membership only while
        -- that native filter is trustworthy: on an explicitly out-of-range
        -- group unit some Classic clients return every aura for |PLAYER.
        local sourceUnit = data.sourceUnit
        local fromPlayer = data.isFromPlayerOrPlayerPet
        -- A trusted positive flag decides at once, before any UnitIsUnit call:
        -- the default "player first" sort asks this for every aura, and a
        -- non-literal source would cost three calls each.
        if lane._msufA3NativePlayerFilterTrusted ~= false
            and fromPlayer ~= nil and not IsSecret(fromPlayer) and fromPlayer == true then
            lane.mine[auraInstanceID] = true
        elseif sourceUnit ~= nil and not IsSecret(sourceUnit) then
            -- The literal tokens are the common case and need no API call.
            local sourceIsPlayer = sourceUnit == "player"
                or sourceUnit == "pet" or sourceUnit == "vehicle"
            if not sourceIsPlayer and UnitIsUnit then
                sourceIsPlayer = UnitIsUnit("player", sourceUnit)
                    or UnitIsUnit("pet", sourceUnit)
                    or UnitIsUnit("vehicle", sourceUnit)
            end
            lane.mine[auraInstanceID] = sourceIsPlayer == true
        else
            lane.mine[auraInstanceID] = lane._msufA3NativePlayerFilterTrusted ~= false
                and not Filtered(unit, auraInstanceID, cfg.playerFilter)
        end
    end
    return data
end

local function Blacklisted(cfg, data)
    local blacklist = cfg.blacklist
    if not blacklist then return false end
    local spellID = data and data.spellId
    if spellID == nil or IsSecret(spellID) then return false end
    if type(spellID) == "number" then
        return blacklist[spellID] == true
    end
    spellID = tonumber(spellID)
    return spellID and blacklist[math_floor(spellID + 0.5)] == true or false
end

local function MatchFilter(unit, auraInstanceID, filter)
    return not Filtered(unit, auraInstanceID, filter)
end

local function MatchDispelTrigger(lane, unit, data, trigger)
    if not (lane and data) then return false end
    if trigger == "ANY_DEBUFF" then
        return true
    elseif trigger == "PLAYER_CAST" then
        return lane.mine[data.auraInstanceID] == true
    elseif trigger == "DISPEL_TYPE" then
        local dispelName = PlainString(data.dispelName)
        return dispelName ~= nil and dispelName ~= ""
    end
    return MatchFilter(unit, data.auraInstanceID, lane.config.dispellableFilter)
end

--- The one Hide permanent predicate: Buff/Debuff, group and custom container
--- lanes all ask it (ShouldShowAura hands it to Features.MatchAura), so one aura
--- is never permanent in one lane and timed in another. false is permanent,
--- nil is unreadable and stays visible.
local function TimedAura(unit, data)
    local duration = PlainNumber(data and data.duration)
    local expirationTime = PlainNumber(data and data.expirationTime)
    if duration ~= nil and expirationTime ~= nil then
        return duration > 0 and expirationTime > 0
    end

    -- Group-unit AuraData may protect the raw duration fields even though the
    -- permanent/timed distinction is still available through the sanctioned
    -- LuaDurationObject API. IsZero is scale-independent, so it is also safe
    -- on the Classic clients where binding this object as a cooldown produced
    -- millisecond/second drift. Keep an unreadable result indeterminate rather
    -- than misclassifying every protected timed aura as permanent.
    local auraInstanceID = data and data.auraInstanceID
    local getAuraDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
    if unit ~= nil and auraInstanceID ~= nil and not IsSecret(auraInstanceID)
        and type(getAuraDuration) == "function" then
        local durationObject = getAuraDuration(unit, auraInstanceID)
        local isZero = durationObject and durationObject.IsZero
        if type(isZero) == "function" then
            local zero = isZero(durationObject)
            if not IsSecret(zero) then return zero ~= true end
        end
    end
    return nil
end

local function FromAnyPlayerOrPet(data)
    if type(data) ~= "table" then return nil end
    local raw = data.isFromPlayerOrPlayerPet
    if raw ~= nil and not IsSecret(raw) and raw == true then return true end

    -- Supported Classic clients expose the AuraData flag, but some Mists/TBC
    -- group payloads report false/nil for player-owned effects. Use the public
    -- source token to reject those false negatives before accepting a public
    -- false flag as an environment/NPC aura.
    local sourceUnit = data.sourceUnit
    if sourceUnit ~= nil and not IsSecret(sourceUnit) then
        local isPlayer = type(UnitIsPlayer) == "function" and UnitIsPlayer(sourceUnit) or nil
        if isPlayer ~= nil and not IsSecret(isPlayer) and isPlayer == true then return true end
        local inParty = type(UnitPlayerOrPetInParty) == "function"
            and UnitPlayerOrPetInParty(sourceUnit) or nil
        if inParty ~= nil and not IsSecret(inParty) and inParty == true then return true end
        local inRaid = type(UnitPlayerOrPetInRaid) == "function"
            and UnitPlayerOrPetInRaid(sourceUnit) or nil
        if inRaid ~= nil and not IsSecret(inRaid) and inRaid == true then return true end
    end

    if raw ~= nil and not IsSecret(raw) then return raw == true end
    return nil
end

local function SatedAura(data)
    local spellID = data and data.spellId
    if spellID == nil or IsSecret(spellID) then return false end
    if type(spellID) == "number" then
        return SATED_SPELLS[spellID] == true
    end
    spellID = tonumber(spellID)
    return spellID and SATED_SPELLS[math_floor(spellID + 0.5)] == true or false
end

local function ShouldShowAura(lane, unit, data)
    local cfg = lane.config
    local features = Features or A3.ClassicFeatures
    if features and type(features.IsAutoExcluded) == "function"
        and features.IsAutoExcluded(cfg, data) then
        return false
    end
    if Blacklisted(cfg, data) then return false end
    local mine = lane.mine[data.auraInstanceID] == true
    if cfg.classicFeatureMatch == true and features
        and type(features.MatchAura) == "function" then
        return features.MatchAura(cfg, unit, data, MatchFilter, TimedAura, mine)
    end
    if type(cfg.includeSpellIDs) == "table" then
        local spellID = data and data.spellId
        local matched = spellID ~= nil and not IsSecret(spellID)
            and cfg.includeSpellIDs[tonumber(spellID)] == true
        if not matched and type(cfg.includeSpellNames) == "table" then
            -- Rank/alias drift: fall back to the aura name so a whitelisted
            -- spell still matches when the live aura reports another spellId.
            local name = data and data.name
            matched = name ~= nil and not IsSecret(name)
                and cfg.includeSpellNames[name] == true
        end
        if not matched then return false end
    end
    if cfg.nonPlayerFilter == true and FromAnyPlayerOrPet(data) ~= false then return false end
    if cfg.hidePermanent == true and TimedAura(unit, data) == false then return false end
    if cfg.maxDuration and cfg.maxDuration > 0 then
        local duration = PlainNumber(data and data.duration) or 0
        if duration > cfg.maxDuration then return false end
    end
    if cfg.satedFilter == true and SatedAura(data) then
        if cfg.showSated ~= true then return false end
        local threshold = cfg.satedThreshold or 0
        local remaining = threshold > 0 and RemainingTime(data) or nil
        if remaining and remaining > threshold then return false end
    end
    if cfg.filterRequirements and features
        and type(features.MatchFilterRequirements) == "function" then
        return features.MatchFilterRequirements(
            cfg.filterPlan or cfg.filterRequirements, unit, data, MatchFilter, mine)
    end
    if not cfg.hasFilterWork then return true end
    local auraInstanceID = data.auraInstanceID
    if cfg.exclusiveImportant then
        return MatchFilter(unit, auraInstanceID, cfg.importantFilter)
    end
    if cfg.onlyImportant and not cfg.hasInclusive then
        return MatchFilter(unit, auraInstanceID, cfg.importantFilter)
    end
    if cfg.hasInclusive then
        if cfg.onlyMine and mine then return true end
        if cfg.raid and MatchFilter(unit, auraInstanceID, cfg.raidFilter) then return true end
        if cfg.raidInCombat and MatchFilter(unit, auraInstanceID, cfg.raidInCombatFilter) then return true end
        if cfg.includeStealable and MatchFilter(unit, auraInstanceID, cfg.stealableFilter) then return true end
        if cfg.boss and MatchFilter(unit, auraInstanceID, cfg.bossFilter) then return true end
        if cfg.onlyImportant and MatchFilter(unit, auraInstanceID, cfg.importantFilter) then return true end
        return false
    end
    return true
end

local function DataMatchesLane(data, cfg)
    if type(data) == "table" then
        local harmful = data.isHarmful
        if harmful ~= nil and not IsSecret(harmful) then
            return (harmful == true) == (cfg.harmful == true)
        end
        local helpful = data.isHelpful
        if helpful ~= nil and not IsSecret(helpful) then
            return (helpful == true) ~= (cfg.harmful == true)
        end
    end
    local auraInstanceID = data and data.auraInstanceID
    return auraInstanceID ~= nil and not Filtered(cfg.unit, auraInstanceID, cfg.filter)
end

Filters.TokenSet = TokenSet
Filters.TokenSerial = TokenSerial
Filters.TokenTrust = TokenTrust
Filters.ProcessData = ProcessData
Filters.MatchDispelTrigger = MatchDispelTrigger
Filters.ShouldShowAura = ShouldShowAura
Filters.DataMatchesLane = DataMatchesLane
Backend.Filters = Filters
