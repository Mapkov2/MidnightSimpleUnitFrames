local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

local AuraCache = GF.AuraCache or {}
GF.AuraCache = AuraCache

local C_UnitAuras = C_UnitAuras
local UnitClass = UnitClass
local tonumber = tonumber
local type = type
local pairs = pairs
local wipe = _G.wipe or table.wipe
local issecretvalue = _G.issecretvalue

local EMPTY = {}
AuraCache.EMPTY = EMPTY

-- WoW marks select aura fields (spellId/name/icon/dispelName/sourceUnit/etc.)
-- as "secret values" when reading them on the local player would leak hidden
-- info. Using a secret value as a table key, as input to tonumber, or in a
-- comparison raises "attempted to index a table that cannot be indexed with
-- secret keys" / "attempt to compare ... a secret ... value". Every aura
-- field we use as a key OR coerce numerically MUST pass through IsSecret
-- first.
--
-- `issecretvalue` is a C builtin that returns true for secret values, nil
-- otherwise. It never throws — calling it on a normal value just returns nil.
-- We bind it to a direct local so each call site costs a single C-function
-- dispatch with no Lua wrapper overhead.
local IsSecret = issecretvalue or function(_) return false end
AuraCache.IsSecret = IsSecret

function AuraCache.BoolIsTrue(value)
    if IsSecret(value) then return false end
    return value == true or value == 1
end

function AuraCache.BoolIsFalse(value)
    if IsSecret(value) then return false end
    return value == false or value == 0
end

local DISPEL_CLASS = {
    DRUID = { Curse = true, Poison = true, Magic = true },
    EVOKER = { Curse = true, Poison = true, Magic = true },
    MAGE = { Curse = true },
    MONK = { Disease = true, Poison = true, Magic = true },
    PALADIN = { Disease = true, Poison = true, Magic = true },
    PRIEST = { Disease = true, Magic = true },
    SHAMAN = { Curse = true, Magic = true },
}

function AuraCache.SetShown(region, show)
    if region and region._msufGFShown ~= show then
        region:SetShown(show)
        region._msufGFShown = show
    end
end

local function PlayerCanDispel(dispelName)
    if not dispelName then return false end
    local _, class = UnitClass("player")
    local map = class and DISPEL_CLASS[class]
    if not map then return true end
    return map[dispelName] == true
end

local function AuraFromPlayer(data)
    -- WoW's AuraData reliably populates isFromPlayerOrPlayerPet as a bool.
    -- Don't call UnitIsUnit here as a fallback — it's locked down and can
    -- taint the caller chain. If the bool is nil/secret, treat as not-ours.
    local fromPlayer = data.isFromPlayerOrPlayerPet
    if fromPlayer == nil or IsSecret(fromPlayer) then
        return false
    end
    return fromPlayer == true or fromPlayer == 1
end

local function GetAuraSlots(unit, filter, maxSlots)
    if not (C_UnitAuras and C_UnitAuras.GetAuraSlots and unit) then
        return nil
    end
    local continuationToken, slots = C_UnitAuras.GetAuraSlots(unit, filter, maxSlots)
    if type(slots) == "table" then
        return slots
    end
    return type(continuationToken) == "table" and continuationToken or nil
end

local function GetAuraDataBySlot(unit, slot)
    return C_UnitAuras and C_UnitAuras.GetAuraDataBySlot and C_UnitAuras.GetAuraDataBySlot(unit, slot) or nil
end

local function GetAuraDataByInstance(unit, auraInstanceID)
    return C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
        and C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
        or nil
end

local function AuraInstanceID(data)
    return data and (data.auraInstanceID or data.auraInstanceId)
end

local function ClassifyAura(data, fallback)
    if fallback ~= nil then return fallback == true end
    local harmful = data and data.isHarmful
    if harmful ~= nil then return harmful == true or harmful == 1 end
    local helpful = data and data.isHelpful
    if helpful ~= nil then return not (helpful == true or helpful == 1) end
    return nil
end

local function NewSnapshot(unit)
    return {
        unit = unit,
        valid = false,
        revision = 0,
        buffIcons = {},
        debuffIcons = {},
        helpfulById = {},
        harmfulById = {},
        playerHelpfulById = {},
        playerHarmfulById = {},
        helpfulByName = {},
        harmfulByName = {},
        playerHelpfulByName = {},
        playerHarmfulByName = {},
        instanceData = {},
        instanceHarmful = {},
        helpfulOrder = {},
        harmfulOrder = {},
        anyDebuff = false,
        anyDispelType = false,
        dispellable = false,
        byMe = false,
    }
end

local function ResetDerived(snapshot)
    wipe(snapshot.buffIcons)
    wipe(snapshot.debuffIcons)
    wipe(snapshot.helpfulById)
    wipe(snapshot.harmfulById)
    wipe(snapshot.playerHelpfulById)
    wipe(snapshot.playerHarmfulById)
    wipe(snapshot.helpfulByName)
    wipe(snapshot.harmfulByName)
    wipe(snapshot.playerHelpfulByName)
    wipe(snapshot.playerHarmfulByName)
    snapshot.anyDebuff = false
    snapshot.anyDispelType = false
    snapshot.dispellable = false
    snapshot.byMe = false
end

local function ResetSnapshot(snapshot, unit)
    snapshot.unit = unit
    snapshot.valid = true
    snapshot.revision = (snapshot.revision or 0) + 1
    wipe(snapshot.instanceData)
    wipe(snapshot.instanceHarmful)
    wipe(snapshot.helpfulOrder)
    wipe(snapshot.harmfulOrder)
    ResetDerived(snapshot)
end

local function EnsureSnapshot(frame, unit)
    local snapshot = frame and frame._msufGFAuraSnapshot
    if not snapshot then
        snapshot = NewSnapshot(unit)
        if frame then frame._msufGFAuraSnapshot = snapshot end
    end
    return snapshot
end

local function RemoveFromOrder(order, auraInstanceID)
    for i = 1, #order do
        if order[i] == auraInstanceID then
            for j = i, #order - 1 do
                order[j] = order[j + 1]
            end
            order[#order] = nil
            return
        end
    end
end

local function StoreInstance(snapshot, data, harmful)
    local auraInstanceID = AuraInstanceID(data)
    if not auraInstanceID then return false end
    local oldHarmful = snapshot.instanceHarmful[auraInstanceID]
    if oldHarmful ~= nil and oldHarmful ~= harmful then
        RemoveFromOrder(oldHarmful and snapshot.harmfulOrder or snapshot.helpfulOrder, auraInstanceID)
    end
    if oldHarmful == nil or oldHarmful ~= harmful then
        local order = harmful and snapshot.harmfulOrder or snapshot.helpfulOrder
        order[#order + 1] = auraInstanceID
    end
    snapshot.instanceData[auraInstanceID] = data
    snapshot.instanceHarmful[auraInstanceID] = harmful and true or false
    return true
end

local function RemoveInstance(snapshot, auraInstanceID)
    if not auraInstanceID then return false end
    local harmful = snapshot.instanceHarmful[auraInstanceID]
    if harmful == nil and snapshot.instanceData[auraInstanceID] == nil then return false end
    snapshot.instanceData[auraInstanceID] = nil
    snapshot.instanceHarmful[auraInstanceID] = nil
    RemoveFromOrder(harmful and snapshot.harmfulOrder or snapshot.helpfulOrder, auraInstanceID)
    return true
end

local function IndexAura(snapshot, data, harmful)
    if not data then return end
    -- Cheap checks (nil/type/empty) run BEFORE IsSecret so non-secret nil
    -- fields cost just one branch. IsSecret is the most expensive guard
    -- (C-function call); keep it last in each chain.
    local iconList = harmful and snapshot.debuffIcons or snapshot.buffIcons
    local icon = data.icon
    if icon and not IsSecret(icon) then
        iconList[#iconList + 1] = icon
    end
    local fromPlayer = AuraFromPlayer(data)
    local spellId = data.spellId
    if spellId and not IsSecret(spellId) then
        local id = tonumber(spellId)
        if id then
            local byId = harmful and snapshot.harmfulById or snapshot.helpfulById
            if not byId[id] then byId[id] = data end
            if fromPlayer then
                local playerById = harmful and snapshot.playerHarmfulById or snapshot.playerHelpfulById
                if not playerById[id] then playerById[id] = data end
            end
        end
    end
    local name = data.name
    if name and type(name) == "string" and name ~= "" and not IsSecret(name) then
        local byName = harmful and snapshot.harmfulByName or snapshot.helpfulByName
        if not byName[name] then byName[name] = data end
        if fromPlayer then
            local playerByName = harmful and snapshot.playerHarmfulByName or snapshot.playerHelpfulByName
            if not playerByName[name] then playerByName[name] = data end
        end
    end
    if harmful then
        snapshot.anyDebuff = true
        local dispelName = data.dispelName
        if dispelName and not IsSecret(dispelName) then
            snapshot.anyDispelType = true
            if PlayerCanDispel(dispelName) then
                snapshot.dispellable = true
            end
        end
        if fromPlayer then
            snapshot.byMe = true
        end
    end
end

local function ReindexSnapshot(snapshot)
    ResetDerived(snapshot)
    local dataByInstance = snapshot.instanceData
    local harmfulOrder = snapshot.harmfulOrder
    for i = 1, #harmfulOrder do
        IndexAura(snapshot, dataByInstance[harmfulOrder[i]], true)
    end
    local helpfulOrder = snapshot.helpfulOrder
    for i = 1, #helpfulOrder do
        IndexAura(snapshot, dataByInstance[helpfulOrder[i]], false)
    end
    snapshot.valid = true
    snapshot.revision = (snapshot.revision or 0) + 1
end

local function ScanFilter(snapshot, unit, filter, maxSlots, harmful)
    local slots = GetAuraSlots(unit, filter, maxSlots)
    if not slots then return end
    for i = 1, #slots do
        local data = GetAuraDataBySlot(unit, slots[i])
        if data then
            StoreInstance(snapshot, data, harmful)
        end
    end
end

function AuraCache.BuildSnapshot(frame)
    local unit = frame and frame.unit
    local snapshot = EnsureSnapshot(frame, unit)
    ResetSnapshot(snapshot, unit)
    if unit then
        ScanFilter(snapshot, unit, "HARMFUL", 40, true)
        ScanFilter(snapshot, unit, "HELPFUL", 40, false)
        ReindexSnapshot(snapshot)
    end
    return snapshot
end

function AuraCache.UpdateSnapshot(frame, updateInfo)
    local unit = frame and frame.unit
    local snapshot = EnsureSnapshot(frame, unit)
    if not (unit and updateInfo) or updateInfo.isFullUpdate == true or snapshot.unit ~= unit or snapshot.valid ~= true then
        return AuraCache.BuildSnapshot(frame)
    end

    local changed, needsFull = false, false
    local removed = updateInfo.removedAuraInstanceIDs
    if type(removed) == "table" then
        for i = 1, #removed do
            changed = RemoveInstance(snapshot, removed[i]) or changed
        end
    end

    local updated = updateInfo.updatedAuraInstanceIDs
    if type(updated) == "table" then
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then
            needsFull = #updated > 0
        else
            for i = 1, #updated do
                local auraInstanceID = updated[i]
                local data = GetAuraDataByInstance(unit, auraInstanceID)
                if data then
                    local harmful = ClassifyAura(data, snapshot.instanceHarmful[auraInstanceID])
                    if harmful == nil or not StoreInstance(snapshot, data, harmful) then
                        needsFull = true
                        break
                    end
                    changed = true
                else
                    changed = RemoveInstance(snapshot, auraInstanceID) or changed
                end
            end
        end
    end

    local added = updateInfo.addedAuras
    if not needsFull and type(added) == "table" then
        for i = 1, #added do
            local data = added[i]
            -- ClassifyAura: addedAuras entries carry isHarmful/isHelpful per
            -- the Blizzard AuraData schema, so this returns true/false. The
            -- nil-guard catches a malformed payload and forces a full rescan.
            local harmful = ClassifyAura(data)
            if harmful == nil or not StoreInstance(snapshot, data, harmful) then
                needsFull = true
                break
            end
            changed = true
        end
    end

    if needsFull then
        return AuraCache.BuildSnapshot(frame)
    end
    if changed then
        ReindexSnapshot(snapshot)
    end
    return snapshot
end

function AuraCache.Invalidate(frame)
    local snapshot = frame and frame._msufGFAuraSnapshot
    if snapshot then
        snapshot.valid = false
    end
end

function AuraCache.GetSnapshot(frame)
    local snapshot = frame and frame._msufGFAuraSnapshot
    if snapshot and snapshot.valid == true and snapshot.unit == frame.unit then
        return snapshot
    end
    return AuraCache.BuildSnapshot(frame)
end

local function SelectMap(snapshot, filter, onlyOwn)
    local harmful = type(filter) == "string" and filter:find("HARMFUL", 1, true)
    local player = onlyOwn == true or (type(filter) == "string" and filter:find("PLAYER", 1, true))
    if harmful then
        return player and snapshot.playerHarmfulById or snapshot.harmfulById
    end
    return player and snapshot.playerHelpfulById or snapshot.helpfulById
end

local function SelectNameMap(snapshot, filter, onlyOwn)
    local harmful = type(filter) == "string" and filter:find("HARMFUL", 1, true)
    local player = onlyOwn == true or (type(filter) == "string" and filter:find("PLAYER", 1, true))
    if harmful then
        return player and snapshot.playerHarmfulByName or snapshot.harmfulByName
    end
    return player and snapshot.playerHelpfulByName or snapshot.helpfulByName
end

function AuraCache.FindBySpellIDs(frame, filter, ids, onlyOwn)
    if not ids then return false, nil end
    local snapshot = AuraCache.GetSnapshot(frame)
    local byId = snapshot and SelectMap(snapshot, filter, onlyOwn)
    if not byId then return false, nil end
    for id in pairs(ids) do
        local data = byId[id]
        if data then
            return true, data
        end
    end
    return false, nil
end

function AuraCache.Find(frame, filter, ids, names, onlyOwn)
    local found, data = AuraCache.FindBySpellIDs(frame, filter, ids, onlyOwn)
    if found then return true, data end
    if not names then return false, nil end
    local snapshot = AuraCache.GetSnapshot(frame)
    local byName = snapshot and SelectNameMap(snapshot, filter, onlyOwn)
    if not byName then return false, nil end
    for name in pairs(names) do
        data = byName[name]
        if data then return true, data end
    end
    return false, nil
end

function AuraCache.ContainsAny(frame, watched)
    if not watched then return true end
    local snapshot = AuraCache.GetSnapshot(frame)
    if not snapshot then return false end
    local ids = watched.ids
    if ids then
        for id in pairs(ids) do
            if snapshot.helpfulById[id] or snapshot.harmfulById[id]
                or snapshot.playerHelpfulById[id] or snapshot.playerHarmfulById[id]
            then
                return true
            end
        end
    end
    local names = watched.names
    if names then
        for name in pairs(names) do
            if snapshot.helpfulByName[name] or snapshot.harmfulByName[name]
                or snapshot.playerHelpfulByName[name] or snapshot.playerHarmfulByName[name]
            then
                return true
            end
        end
    end
    return false
end

local GroupAuraCache = {}

function GroupAuraCache.IsEnabled(frame, spec)
    if not (spec and spec.scope == "group") then
        return false
    end
    if spec.cornerIndicators and spec.cornerIndicators.enabled == true
        and spec.cornerIndicators.needsAura == true then
        return true
    end
    if spec.spellIndicators and spec.spellIndicators.enabled == true
        and #(spec.spellIndicators.items or EMPTY) > 0 then
        return true
    end
    local group = spec.group
    if group and (group.dispelOverlayEnabled == true or group.debuffStripeEnabled == true) then
        return not (spec.auras and spec.auras.enabled == true)
    end
    return false
end

function GroupAuraCache.GetEvents()
    return { "UNIT_AURA" }
end

function GroupAuraCache.Apply(frame)
    AuraCache.BuildSnapshot(frame)
end

function GroupAuraCache.Update(frame, event, unit, updateInfo)
    if event == "UNIT_AURA" then
        AuraCache.UpdateSnapshot(frame, updateInfo)
    else
        AuraCache.BuildSnapshot(frame)
    end
end

if UF and UF.RegisterElement then
    UF.RegisterElement("GroupAuraCache", GroupAuraCache)
end
