local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

local AuraCache = GF.AuraCache or {}
GF.AuraCache = AuraCache
local DispelState = UF and UF.DispelState or {}

local C_UnitAuras = C_UnitAuras
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

function AuraCache.SetShown(region, show)
    if region and region._msufGFShown ~= show then
        region:SetShown(show)
        region._msufGFShown = show
    end
end

local function SafeString(value)
    if value == nil or IsSecret(value) or type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

local function SafeDispelName(value)
    value = SafeString(value)
    if value == "None" then return nil end
    return value
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

local function CaptureAuraSlots(buffer, ...)
    local n = select("#", ...)
    local count = 0
    for i = 1, n do
        local value = select(i, ...)
        if type(value) == "table" then
            return value
        elseif type(value) == "number" then
            count = count + 1
            buffer[count] = value
        end
    end
    for i = count + 1, #buffer do
        buffer[i] = nil
    end
    return count > 0 and buffer or nil
end

local function GetAuraSlots(unit, filter, maxSlots, buffer)
    if not (C_UnitAuras and C_UnitAuras.GetAuraSlots and unit) then
        return nil
    end
    return CaptureAuraSlots(buffer or EMPTY, C_UnitAuras.GetAuraSlots(unit, filter, maxSlots))
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
    if not data then return nil end
    local auraInstanceID = data.auraInstanceID
    if auraInstanceID ~= nil then return auraInstanceID end
    return data.auraInstanceId
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
        instanceData = {},
        instanceHarmful = {},
        helpfulOrder = {},
        harmfulOrder = {},
        slotBuffer = {},
        anyDebuff = false,
        anyDispelType = false,
        dispellable = false,
        dispellableByMe = false,
        byMe = false,
        playerCastDebuff = false,
        dispelAuraInstanceID = nil,
        anyDispelAuraInstanceID = nil,
        anyDebuffAuraInstanceID = nil,
        dispelName = nil,
        anyDispelName = nil,
    }
end

local function ResetDerived(snapshot)
    wipe(snapshot.buffIcons)
    wipe(snapshot.debuffIcons)
    snapshot.anyDebuff = false
    snapshot.anyDispelType = false
    snapshot.dispellable = false
    snapshot.dispellableByMe = false
    snapshot.byMe = false
    snapshot.playerCastDebuff = false
    snapshot.dispelAuraInstanceID = nil
    snapshot.anyDispelAuraInstanceID = nil
    snapshot.anyDebuffAuraInstanceID = nil
    snapshot.dispelName = nil
    snapshot.anyDispelName = nil
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
    snapshot.frame = frame
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
    local iconList = harmful and snapshot.debuffIcons or snapshot.buffIcons
    local icon = data.icon
    if icon ~= nil and not IsSecret(icon) then
        iconList[#iconList + 1] = icon
    end
    local fromPlayer = AuraFromPlayer(data)
    if harmful then
        snapshot.anyDebuff = true
        local auraInstanceID = AuraInstanceID(data)
        if auraInstanceID and not snapshot.anyDebuffAuraInstanceID then
            snapshot.anyDebuffAuraInstanceID = auraInstanceID
        end
        local dispelName = SafeDispelName(data.dispelName)
        if dispelName then
            snapshot.anyDispelType = true
            snapshot.anyDispelName = snapshot.anyDispelName or dispelName
            snapshot.anyDispelAuraInstanceID = snapshot.anyDispelAuraInstanceID or auraInstanceID
        end
        if DispelState.AuraCanActivePlayerDispel and DispelState.AuraCanActivePlayerDispel(data) then
            snapshot.anyDispelType = true
            snapshot.anyDispelName = snapshot.anyDispelName or dispelName or "DISPELLABLE"
            snapshot.anyDispelAuraInstanceID = snapshot.anyDispelAuraInstanceID or auraInstanceID
            snapshot.dispellable = true
            snapshot.dispellableByMe = true
            snapshot.dispelName = snapshot.dispelName or dispelName
            snapshot.dispelAuraInstanceID = snapshot.dispelAuraInstanceID or auraInstanceID
        end
        if fromPlayer then
            snapshot.byMe = true
            snapshot.playerCastDebuff = true
        end
    end
end

local function SnapshotNeedsDirectDispel(snapshot)
    local spec = snapshot and snapshot.frame and snapshot.frame.MSUFSpec
    local cfg = spec and spec.cornerIndicators
    local slots = cfg and cfg.slots
    if type(slots) ~= "table" then return false end
    for i = 1, #slots do
        if slots[i] and slots[i].category == "dispel" then return true end
    end
    return false
end

local function MergeDirectDispelSnapshot(snapshot)
    if not (snapshot and snapshot.unit and DispelState.Update) then return end
    if not SnapshotNeedsDirectDispel(snapshot) then return end
    if snapshot.dispellableByMe == true and snapshot.dispelAuraInstanceID then return end
    local direct = DispelState.Update(snapshot.frame or snapshot.unit, {
        needAnyDebuff = false,
        needAnyDispelType = false,
        needDispellable = true,
        needPlayerCast = false,
    })
    if not direct then return end
    if direct.dispellableByMe == true then
        snapshot.anyDebuff = true
        snapshot.anyDispelType = true
        snapshot.dispellable = true
        snapshot.dispellableByMe = true
        snapshot.dispelAuraInstanceID = snapshot.dispelAuraInstanceID or direct.dispelAuraInstanceID
        snapshot.anyDispelAuraInstanceID = snapshot.anyDispelAuraInstanceID or direct.anyDispelAuraInstanceID
        snapshot.anyDebuffAuraInstanceID = snapshot.anyDebuffAuraInstanceID or direct.anyDebuffAuraInstanceID
        snapshot.dispelName = snapshot.dispelName or direct.dispelName
        snapshot.anyDispelName = snapshot.anyDispelName or direct.anyDispelName
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
    MergeDirectDispelSnapshot(snapshot)
    snapshot.valid = true
    snapshot.revision = (snapshot.revision or 0) + 1
end

local function ScanFilter(snapshot, unit, filter, maxSlots, harmful)
    local slots = GetAuraSlots(unit, filter, maxSlots, snapshot.slotBuffer)
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

local function SelectOrder(snapshot, filter)
    local harmful = type(filter) == "string" and filter:find("HARMFUL", 1, true)
    if harmful then
        return snapshot.harmfulOrder
    end
    return snapshot.helpfulOrder
end

function AuraCache.Find(frame, filter, ids, names, onlyOwn)
    local snapshot = AuraCache.GetSnapshot(frame)
    if not snapshot then return false, nil end
    local order = SelectOrder(snapshot, filter)
    local playerReq = onlyOwn == true or (type(filter) == "string" and filter:find("PLAYER", 1, true))

    for i = 1, #order do
        local data = snapshot.instanceData[order[i]]
        if data and (not playerReq or AuraFromPlayer(data)) then
            if ids and data.spellId and not IsSecret(data.spellId) and ids[tonumber(data.spellId)] then
                return true, data
            end
            if names and data.name and not IsSecret(data.name) and names[data.name] then
                return true, data
            end
        end
    end
    return false, nil
end

function AuraCache.FindBySpellIDs(frame, filter, ids, onlyOwn)
    return AuraCache.Find(frame, filter, ids, nil, onlyOwn)
end

function AuraCache.ContainsAny(frame, watched)
    if not watched then return true end
    local snapshot = AuraCache.GetSnapshot(frame)
    if not snapshot then return false end

    local function checkOrder(order)
        for i = 1, #order do
            local data = snapshot.instanceData[order[i]]
            if data then
                if watched.ids and data.spellId and not IsSecret(data.spellId) and watched.ids[tonumber(data.spellId)] then
                    return true
                end
                if watched.names and data.name and not IsSecret(data.name) and watched.names[data.name] then
                    return true
                end
            end
        end
        return false
    end

    return checkOrder(snapshot.harmfulOrder) or checkOrder(snapshot.helpfulOrder)
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
    return false
end

function GroupAuraCache.GetEvents()
    return { "UNIT_AURA" }
end

local DISPEL_CAPABILITY_EVENTS = {
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "SPELLS_CHANGED",
}

local function CornerNeedsDispel(spec)
    local cfg = spec and spec.cornerIndicators
    local slots = cfg and cfg.slots
    if type(slots) ~= "table" then return false end
    for i = 1, #slots do
        if slots[i] and slots[i].category == "dispel" then return true end
    end
    return false
end

function GroupAuraCache.GetUnitlessEvents(frame, spec)
    return CornerNeedsDispel(spec) and DISPEL_CAPABILITY_EVENTS or nil
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
