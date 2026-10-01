local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Game/Forever/GroupFrames/MSUF_GroupFrames_BuffCoverage.lua
--- Buff coverage icons on party and raid frames, WoW Forever only.
---
--- A member's frame shows one small icon for every long-duration class buff
--- that a class in the group can cast but the member does not carry. Only the
--- Mainline group manifest loads this file, and it returns at once on every
--- client that is not WoW Forever.
---
--- How auras are read:
---   * UNIT_AURA is registered per group unit token, two tokens per listener
---     frame, so nameplates, targets and every other unit never reach Lua.
---   * The event payload is applied incrementally: an added aura is matched by
---     its spell ID, a removed one by the auraInstanceID recorded when it was
---     added. A member is read in full only after a full update, a roster
---     change that gives the token to someone else, or a restriction ending.
---   * While combat, an encounter, a challenge mode or a PvP match restricts
---     aura data, only auras that are still readable are looked at, at most
---     twice a second: they can show that a buff arrived, and a buff whose
---     every spell ID Blizzard flags never secret can also be found missing.
---     Everything else keeps the state it had when the restriction began, and
---     the listeners stay off for the fight when no buff can be read at all.
---     A member whose state is unknown never shows an icon.
local _, MSUF = ...
local Client = MSUF.Client
if not (Client and Client.IsForever == true) then return end
local GF = MSUF.GF
local UnitAuraAPI = _G.C_UnitAuras
local GetUnitAuras = UnitAuraAPI and UnitAuraAPI.GetUnitAuras
if not (GF and type(GetUnitAuras) == "function") then return end

local CreateFrame, C_Timer = CreateFrame, C_Timer
local UnitClass, UnitGUID = UnitClass, UnitGUID
local UnitIsConnected, UnitIsVisible = UnitIsConnected, UnitIsVisible
local GetNumGroupMembers, GetNumSubgroupMembers, IsInRaid = GetNumGroupMembers, GetNumSubgroupMembers, IsInRaid
local issecretvalue = _G.issecretvalue or function() return false end
local floor, max, min, tonumber, pairs, wipe = math.floor, math.max, math.min, tonumber, pairs, wipe

-- Buffs by the class that casts them. "ids" lists, in ascending order, every
-- spell ID whose English name in the WoW Forever SpellName table (client build
-- 1.60.1.70009, the same table as Game/Forever/Auras/AliasData) is the name of
-- one of the buff's spells: each rank of the single-target spell, the
-- group-wide version and same-named variants. Any one of them counts.
-- "need" decides who should carry the buff: every member, members of a mana
-- class, or members holding the Tank role.
local BUFFS_BY_CLASS = {
    DRUID = {
        -- Mark of the Wild and Gift of the Wild.
        { key = "Wild", need = "all", ids = {
            1126, 5232, 5234, 5286, 5287, 6756, 8907, 8908, 9884, 9885, 16878,
            21849, 21850, 24752, 364163, 1291335, 1310503 } },
        -- Thorns.
        { key = "Thorns", need = "tank", ids = {
            467, 782, 1075, 8914, 9756, 9910, 15438, 16877, 21335, 21337, 22128,
            22351, 22696, 25640, 25777, 438294, 438326, 1213813, 1213816, 1213834,
            1236308, 1291338, 1312955 } },
    },
    MAGE = {
        -- Arcane Intellect and Arcane Brilliance.
        { key = "Intellect", need = "mana", ids = {
            1459, 1460, 1461, 10156, 10157, 13326, 16876, 23028, 364161 } },
    },
    PALADIN = {
        -- One paladin blessing of any kind, normal or greater: Might, Wisdom,
        -- Kings, Salvation, Light and Sanctuary.
        { key = "Blessings", need = "all", ids = {
            1038, 19740, 19742, 19834, 19835, 19836, 19837, 19838, 19850, 19852,
            19853, 19854, 19977, 19978, 19979, 20217, 20911, 25290, 25291, 25782,
            25890, 25894, 25895, 25898, 25899, 25916, 25918, 26650, 1213408 } },
    },
    PRIEST = {
        -- Power Word: Fortitude and Prayer of Fortitude.
        { key = "Stamina", need = "all", ids = {
            1243, 1244, 1245, 2791, 10937, 10938, 10939, 10940, 13864, 21562,
            21564, 23947, 23948, 450086 } },
        -- Divine Spirit and Prayer of Spirit.
        { key = "Spirit", need = "mana", ids = {
            14752, 14818, 14819, 16875, 27681, 27841 } },
    },
}
local CLASS_ORDER = { "DRUID", "MAGE", "PALADIN", "PRIEST" }
-- Classic Era classes whose primary resource is mana (a shapeshifted druid
-- still counts). Warriors and rogues never need Intellect or Spirit.
local MANA_CLASSES = { DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true, SHAMAN = true, WARLOCK = true }
local SCOPES = { "party", "raid", "mythicraid" }

local BUFFS, BUFF_OF_SPELL = {}, {}
for c = 1, #CLASS_ORDER do
    local class = CLASS_ORDER[c]
    local list = BUFFS_BY_CLASS[class]
    for b = 1, #list do
        local buff = list[b]
        buff.class, buff.setting = class, "buffCoverage" .. buff.key
        BUFFS[#BUFFS + 1] = buff
        for i = 1, #buff.ids do BUFF_OF_SPELL[buff.ids[i]] = #BUFFS end
    end
end
local BUFF_COUNT = #BUFFS
GF.BUFF_COVERAGE_BUFFS = BUFFS

local RAID_UNITS, PARTY_UNITS = {}, {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i end

local states = {}          -- unit token -> what the last reads proved
local providers = {}       -- class token -> true while someone in the group plays it
local watched, watchedSet = {}, {}
local shards = {}
local dispatcher = CreateFrame("Frame")
local active, restricted, restrictedReads, secrecyChecked = false, false, false, false
local flushQueued, fullPending, restrictedQueued = false, false, false
local pendingUnits, restrictedDirty = {}, {}
local seen, order = {}, {}
local RESTRICTED_READ_DELAY = 0.5

local function IsSecret(value) return issecretvalue(value) == true end

-- A buff whose every ID Blizzard flags never secret stays decidable while
-- auras are restricted; one with some such IDs can still be seen arriving.
local function CheckSecrecy()
    if secrecyChecked then return end
    secrecyChecked = true
    local secrets = _G.C_Secrets
    local getSecrecy = secrets and secrets.GetSpellAuraSecrecy
    local levels = _G.Enum and _G.Enum.SecrecyLevel
    local never = levels and levels.NeverSecret
    for index = 1, BUFF_COUNT do
        local buff = BUFFS[index]
        local all, any = type(getSecrecy) == "function" and never ~= nil, false
        if all then
            for i = 1, #buff.ids do
                if getSecrecy(buff.ids[i]) == never then any = true else all = false end
            end
        end
        buff.alwaysReadable, buff.sometimesReadable = all, any
    end
end

local function State(unit)
    local state = states[unit]
    if not state then
        state = { known = false, count = {}, instance = {} }
        for i = 1, BUFF_COUNT do state.count[i] = 0 end
        states[unit] = state
    end
    return state
end

-- Aura data exists only for connected members the client can see; anything
-- else (another map, out of range, offline) is unknown, never "missing".
local function Reachable(unit)
    local connected, visible = UnitIsConnected(unit), UnitIsVisible(unit)
    return not IsSecret(connected) and connected == true and not IsSecret(visible) and visible == true
end

local function ReadUnit(unit)
    local state = State(unit)
    local count, instance = state.count, state.instance
    for i = 1, BUFF_COUNT do count[i] = 0 end
    wipe(instance)
    state.known = false
    if not Reachable(unit) then return state end
    local auras = GetUnitAuras(unit, "HELPFUL")
    if IsSecret(auras) or type(auras) ~= "table" then return state end
    for i = 1, #auras do
        local aura = auras[i]
        if IsSecret(aura) or type(aura) ~= "table" then return state end
        local spellID = aura.spellId
        if IsSecret(spellID) then return state end
        local index = spellID and BUFF_OF_SPELL[spellID]
        if index then
            count[index] = count[index] + 1
            local auraInstanceID = aura.auraInstanceID
            if auraInstanceID ~= nil and not IsSecret(auraInstanceID) then instance[auraInstanceID] = index end
        end
    end
    state.known = true
    return state
end

-- Applies one readable payload. Returns true when the shown result can have
-- changed, false when it cannot, nil when the payload cannot be applied.
local function ApplyUpdate(state, info)
    if IsSecret(info) or type(info) ~= "table" then return nil end
    local full = info.isFullUpdate
    if IsSecret(full) or full ~= false then return nil end
    local count, instance, changed = state.count, state.instance, false
    local added = info.addedAuras
    if IsSecret(added) then return nil end
    if added then
        for i = 1, #added do
            local aura = added[i]
            if IsSecret(aura) or type(aura) ~= "table" then return nil end
            local spellID, auraInstanceID = aura.spellId, aura.auraInstanceID
            if IsSecret(spellID) or IsSecret(auraInstanceID) then return nil end
            local index = spellID and BUFF_OF_SPELL[spellID]
            if index and auraInstanceID ~= nil and instance[auraInstanceID] == nil then
                instance[auraInstanceID] = index
                count[index] = count[index] + 1
                if count[index] == 1 then changed = true end
            end
        end
    end
    -- An updated instance keeps its spell, so updatedAuraInstanceIDs never
    -- changes which buffs are present and is not looked at.
    local removed = info.removedAuraInstanceIDs
    if IsSecret(removed) then return nil end
    if removed then
        for i = 1, #removed do
            local auraInstanceID = removed[i]
            if IsSecret(auraInstanceID) then return nil end
            local index = auraInstanceID ~= nil and instance[auraInstanceID]
            if index then
                instance[auraInstanceID] = nil
                count[index] = max(0, count[index] - 1)
                if count[index] == 0 then changed = true end
            end
        end
    end
    return changed
end

-- Restricted read: only auras that are readable right now take part.
local function ReadRestricted(unit)
    local state = states[unit]
    if not (state and state.known and Reachable(unit)) then return false end
    local auras = GetUnitAuras(unit, "HELPFUL")
    if IsSecret(auras) or type(auras) ~= "table" then return false end
    for index = 1, BUFF_COUNT do seen[index] = false end
    for i = 1, #auras do
        local aura = auras[i]
        if not IsSecret(aura) and type(aura) == "table" then
            local spellID = aura.spellId
            local index = spellID and not IsSecret(spellID) and BUFF_OF_SPELL[spellID]
            if index then seen[index] = true end
        end
    end
    local count, changed = state.count, false
    for index = 1, BUFF_COUNT do
        if seen[index] then
            if count[index] == 0 then count[index], changed = 1, true end
        elseif BUFFS[index].alwaysReadable and count[index] > 0 then
            count[index], changed = 0, true
        end
    end
    return changed
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local ICON_GAP = 2
local FALLBACK_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Texture(buff)
    local texture = buff.texture
    if texture == nil then
        local spellAPI = _G.C_Spell
        local resolve = spellAPI and spellAPI.GetSpellTexture
        texture = type(resolve) == "function" and resolve(buff.ids[1]) or false
        if IsSecret(texture) then texture = false end
        buff.texture = texture
    end
    return texture or FALLBACK_TEXTURE
end

local function Holder(frame)
    local holder = frame._msufBuffCoverage
    if holder then return holder end
    holder = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
    holder:EnableMouse(false)
    holder.icons = {}
    frame._msufBuffCoverage = holder
    return holder
end

local function Icon(holder, slot)
    local icon = holder.icons[slot]
    if icon then return icon end
    icon = PixelLayoutRegion(holder:CreateTexture(nil, "ARTWORK"))
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.edge = PixelLayoutRegion(holder:CreateTexture(nil, "BACKGROUND"))
    icon.edge:SetColorTexture(0, 0, 0, 0.85)
    icon:Hide(); icon.edge:Hide()
    holder.icons[slot] = icon
    return icon
end

-- "Glow missing icons": an orange action-button ring pulses around each icon.
-- The ring art sits inside a larger square, so the texture is scaled past the
-- icon edge the way an action button's border is. Built on first use only.
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local GLOW_SCALE = 1.75

local function Glow(holder, icon)
    local glow = icon.glow
    if glow then return glow end
    glow = PixelLayoutRegion(holder:CreateTexture(nil, "OVERLAY"))
    glow:SetTexture(GLOW_TEXTURE)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.65, 0.1)
    glow:Hide()
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.25)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.6)
    glow.pulse = pulse
    icon.glow = glow
    return glow
end

local function HideGlow(icon)
    local glow = icon.glow
    if glow and glow:IsShown() then
        glow.pulse:Stop()
        glow:Hide()
    end
end

-- Shows or hides one icon's ring; geometry is written only when the icon was
-- placed again or the ring was hidden.
local function SetGlow(holder, icon, on, size, placed)
    if not on then HideGlow(icon); return end
    local glow = Glow(holder, icon)
    local shown = glow:IsShown()
    if placed or not shown then
        local edge = size * GLOW_SCALE
        glow:ClearAllPoints()
        glow:SetPoint("CENTER", icon, "CENTER", 0, 0)
        glow:SetSize(edge, edge)
    end
    if not shown then
        glow:Show()
        glow.pulse:Play()
    end
end

local function HideIcons(frame)
    local holder = frame and frame._msufBuffCoverage
    if holder and holder:IsShown() then
        -- A hidden holder keeps its icons; their rings stop pulsing with it.
        local icons = holder.icons
        for slot = 1, #icons do HideGlow(icons[slot]) end
        holder:Hide()
    end
end
GF.HideBuffCoveragePreview = HideIcons

-- Places `n` icons (BUFFS indices in `list`) as one row at the configured
-- point. Geometry and textures are written only when they change.
local function ShowRow(frame, conf, list, n, scale)
    if n == 0 then HideIcons(frame); return end
    local holder = Holder(frame)
    -- 8-48 px, the missing-buff section's icon size range.
    local size = floor(max(8, min(48, tonumber(conf.buffCoverageSize) or 14)) * scale + 0.5)
    local gap = ICON_GAP * scale
    local point = ANCHORS[conf.buffCoverageAnchor] and conf.buffCoverageAnchor or "BOTTOM"
    local x, y = (tonumber(conf.buffCoverageX) or 0) * scale, (tonumber(conf.buffCoverageY) or 2) * scale
    local layers = MSUF.UF and MSUF.UF.Layers
    local level = layers and layers.StatusLevel and layers.StatusLevel(frame, tonumber(conf.buffCoverageLayer) or 6, 7)
    if level and holder._msufLevel ~= level then holder:SetFrameLevel(level); holder._msufLevel = level end
    if holder._msufPoint ~= point or holder._msufX ~= x or holder._msufY ~= y then
        holder:ClearAllPoints()
        holder:SetPoint(point, frame, point, x, y)
        holder._msufPoint, holder._msufX, holder._msufY = point, x, y
    end
    local resized = holder._msufSize ~= size
    if resized or holder._msufCount ~= n then
        holder:SetSize(n * size + (n - 1) * gap, size)
        holder._msufCount = n
    end
    local icons = holder.icons
    local glow = conf.buffCoverageGlow == true
    for slot = 1, n do
        local icon = Icon(holder, slot)
        local index = list[slot]
        if icon._msufBuff ~= index then icon:SetTexture(Texture(BUFFS[index])); icon._msufBuff = index end
        local placed = resized or not icon:IsShown()
        if placed then
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", holder, "TOPLEFT", (slot - 1) * (size + gap), 0)
            icon:SetSize(size, size)
            icon.edge:ClearAllPoints()
            icon.edge:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
            icon.edge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
            icon:Show(); icon.edge:Show()
        end
        if glow or icon.glow then SetGlow(holder, icon, glow, size, placed) end
    end
    for slot = n + 1, #icons do
        local icon = icons[slot]
        if icon:IsShown() then icon:Hide(); icon.edge:Hide() end
        HideGlow(icon)
    end
    holder._msufSize = size
    if not holder:IsShown() then holder:Show() end
end

-- Menu and Edit Mode samples: every enabled buff, no unit or aura involved.
function GF.RenderBuffCoveragePreview(frame, conf, scale)
    if not (frame and conf and conf.buffCoverageEnabled == true) then HideIcons(frame); return end
    local n = 0
    for index = 1, BUFF_COUNT do
        if conf[BUFFS[index].setting] == true then n = n + 1; order[n] = index end
    end
    ShowRow(frame, conf, order, n, tonumber(scale) or 1)
end

-- "Thorns only on tanks" (on unless turned off) limits the tank buff to members
-- holding the Tank role; off, every member should carry it.
local function Needs(buff, state, unit, conf)
    if buff.need == "mana" then return MANA_CLASSES[state.class] == true end
    if buff.need == "tank" then
        return conf.buffCoverageThornsTankOnly == false or GF.GetUnitGroupRole(unit) == "TANK"
    end
    return true
end

local function PaintFrame(frame, unit)
    if not frame then return end
    local conf = GF.GetConf(frame._msufGFKind or "party")
    if frame._msufGFIsPreviewFrame == true then
        GF.RenderBuffCoveragePreview(frame, conf, 1)
        return
    end
    local state = unit and states[unit]
    if not (conf and conf.buffCoverageEnabled == true and state and state.known)
        or (restricted and conf.buffCoverageCombat ~= true) then
        HideIcons(frame)
        return
    end
    local n = 0
    for index = 1, BUFF_COUNT do
        local buff = BUFFS[index]
        if state.count[index] == 0 and providers[buff.class] and conf[buff.setting] == true and Needs(buff, state, unit, conf) then
            n = n + 1
            order[n] = index
        end
    end
    ShowRow(frame, conf, order, n, 1)
end

local function PaintUnit(unit)
    GF.ForEachFrameForUnit(unit, PaintFrame)
end

local function PaintAll()
    GF.ForEachFrame(PaintFrame, true)
end

---------------------------------------------------------------------------
-- Roster, listeners and restriction state
---------------------------------------------------------------------------
local function AnyScopeEnabled()
    for i = 1, #SCOPES do
        local conf = GF.GetConf(SCOPES[i])
        if conf and conf.buffCoverageEnabled == true then return true end
    end
    return false
end

-- Restricted reads only pay off where icons stay visible during combat and at
-- least one enabled buff there can still be read.
local function NeedsRestrictedReads()
    for i = 1, #SCOPES do
        local conf = GF.GetConf(SCOPES[i])
        if conf and conf.buffCoverageEnabled == true and conf.buffCoverageCombat == true then
            for index = 1, BUFF_COUNT do
                local buff = BUFFS[index]
                if buff.sometimesReadable and conf[buff.setting] == true then return true end
            end
        end
    end
    return false
end

local function QueueFlush()
    if not flushQueued then
        flushQueued = true
        C_Timer.After(0, dispatcher.Flush)
    end
end

local function RunRestrictedReads()
    restrictedQueued = false
    if not restricted then return end
    for unit in pairs(restrictedDirty) do
        restrictedDirty[unit] = nil
        if ReadRestricted(unit) then PaintUnit(unit) end
    end
end

local function OnShardEvent(_, _, unit, info)
    if IsSecret(unit) or not watchedSet[unit] then return end
    if restricted then
        if not restrictedReads then return end
        restrictedDirty[unit] = true
        if not restrictedQueued then
            restrictedQueued = true
            C_Timer.After(RESTRICTED_READ_DELAY, RunRestrictedReads)
        end
        return
    end
    local state = states[unit]
    local changed
    if state and state.known then changed = ApplyUpdate(state, info) end
    if changed == nil then
        pendingUnits[unit] = true
        QueueFlush()
    elseif changed then
        PaintUnit(unit)
    end
end

local function SyncShards()
    restrictedReads = active and restricted and NeedsRestrictedReads()
    local listen = active and (not restricted or restrictedReads)
    local needed = listen and floor((#watched + 1) / 2) or 0
    for s = 1, needed do
        local first, second = watched[2 * s - 1], watched[2 * s]
        local shard = shards[s]
        if not shard then
            shard = CreateFrame("Frame")
            shard:SetScript("OnEvent", OnShardEvent)
            shards[s] = shard
        end
        if shard._msufFirst ~= first or shard._msufSecond ~= second or not shard._msufListening then
            shard:UnregisterEvent("UNIT_AURA")
            if second then shard:RegisterUnitEvent("UNIT_AURA", first, second)
            else shard:RegisterUnitEvent("UNIT_AURA", first) end
            shard._msufFirst, shard._msufSecond, shard._msufListening = first, second, true
        end
    end
    for s = needed + 1, #shards do
        local shard = shards[s]
        if shard._msufListening then
            shard:UnregisterEvent("UNIT_AURA")
            shard._msufFirst, shard._msufSecond, shard._msufListening = nil, nil, false
        end
    end
end

-- Rebuilds the watched tokens and the casting classes. A token that now
-- belongs to someone else loses what was known about its previous owner.
local function ReadRoster()
    wipe(providers)
    wipe(watchedSet)
    local n = 0
    if IsInRaid() then
        for i = 1, min(40, GetNumGroupMembers() or 0) do n = n + 1; watched[n] = RAID_UNITS[i] end
    else
        n = 1
        watched[1] = "player"
        for i = 1, min(4, GetNumSubgroupMembers() or 0) do n = n + 1; watched[n] = PARTY_UNITS[i] end
    end
    for i = n + 1, #watched do watched[i] = nil end
    for i = 1, n do
        local unit = watched[i]
        watchedSet[unit] = true
        local state = State(unit)
        local _, class = UnitClass(unit)
        if IsSecret(class) then class = nil end
        if class then providers[class] = true end
        local guid = UnitGUID(unit)
        if IsSecret(guid) or guid == nil or guid ~= state.guid then
            state.known = false
            state.guid = not IsSecret(guid) and guid or nil
        end
        state.class = class
    end
end

function dispatcher.Flush()
    flushQueued = false
    local wasActive = active
    active = AnyScopeEnabled()
    if not active then
        if wasActive then SyncShards(); PaintAll() end
        fullPending = false
        wipe(pendingUnits)
        return
    end
    CheckSecrecy()
    if fullPending or not wasActive then
        if not wasActive then
            for _, state in pairs(states) do state.known = false end
        end
        ReadRoster()
        SyncShards()
        if not restricted then
            for i = 1, #watched do
                local unit = watched[i]
                if not states[unit].known then ReadUnit(unit) end
            end
        end
        fullPending = false
        wipe(pendingUnits)
        PaintAll()
        return
    end
    for unit in pairs(pendingUnits) do
        pendingUnits[unit] = nil
        if watchedSet[unit] and not restricted then ReadUnit(unit) end
        PaintUnit(unit)
    end
end

local function RequestFull()
    fullPending = true
    QueueFlush()
end
GF.RefreshBuffCoverage = RequestFull

local function SetRestricted(value)
    value = value == true
    if value == restricted then return end
    restricted = value
    if restricted then
        wipe(restrictedDirty)
        SyncShards()
        PaintAll()
    else
        -- Readable again: every member is read once, in one coalesced pass.
        for _, state in pairs(states) do state.known = false end
        RequestFull()
    end
end

-- ADDON_RESTRICTION_STATE_CHANGED fires before a restriction is enforced and
-- after it ends. Only the four kinds that make aura data secret matter.
local ENUM = _G.Enum
local RESTRICTION = ENUM and ENUM.AddOnRestrictionType
local RESTRICTION_STATE = ENUM and ENUM.AddOnRestrictionState
local AURA_RESTRICTIONS = {}
if RESTRICTION then
    for _, name in ipairs({ "Combat", "Encounter", "ChallengeMode", "PvPMatch" }) do
        if RESTRICTION[name] ~= nil then AURA_RESTRICTIONS[RESTRICTION[name]] = true end
    end
end
local restrictionEvents = RESTRICTION_STATE ~= nil and RESTRICTION_STATE.Inactive ~= nil and next(AURA_RESTRICTIONS) ~= nil
    and (type(Client.SupportsEvent) ~= "function" or Client.SupportsEvent("ADDON_RESTRICTION_STATE_CHANGED"))
local activeRestrictions = {}

local function RestrictedNow()
    wipe(activeRestrictions)
    local actions = _G.C_RestrictedActions
    local isActive = actions and actions.IsAddOnRestrictionActive
    if restrictionEvents and type(isActive) == "function" then
        for kind in pairs(AURA_RESTRICTIONS) do
            if isActive(kind) == true then activeRestrictions[kind] = true end
        end
        return next(activeRestrictions) ~= nil
    end
    local secrets = _G.C_Secrets
    if secrets and type(secrets.ShouldAurasBeSecret) == "function" then
        return secrets.ShouldAurasBeSecret() == true
    end
    return InCombatLockdown() == true
end

dispatcher:SetScript("OnEvent", function(_, event, kind, stateValue)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if not AURA_RESTRICTIONS[kind] then return end
        activeRestrictions[kind] = stateValue ~= RESTRICTION_STATE.Inactive or nil
        SetRestricted(next(activeRestrictions) ~= nil)
    elseif event == "PLAYER_REGEN_DISABLED" then
        SetRestricted(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        SetRestricted(RestrictedNow())
    elseif event == "PLAYER_ROLES_ASSIGNED" then
        if active then PaintAll() end
    else
        if event == "PLAYER_ENTERING_WORLD" then
            -- A loading screen can change every member's auras unseen.
            for _, state in pairs(states) do state.known = false end
            restricted = RestrictedNow()
            wipe(restrictedDirty)
        end
        RequestFull()
    end
end)
dispatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
dispatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
dispatcher:RegisterEvent("PLAYER_ROLES_ASSIGNED")
if restrictionEvents then
    dispatcher:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
else
    dispatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    dispatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Settings, rebuilds and frame binding changes arrive through the group
-- runtime; each one is folded into the next coalesced pass.
GF.RegisterRuntimeObserver("buff-coverage", RequestFull)
GF.RegisterFrameRegistryObserver("buff-coverage", function(operation, frame, _, newUnit)
    if operation ~= "track" or not newUnit or not active then HideIcons(frame); return end
    local state = states[newUnit]
    if state and state.known then
        PaintFrame(frame, newUnit)
        return
    end
    HideIcons(frame)
    if watchedSet[newUnit] then
        pendingUnits[newUnit] = true
        QueueFlush()
    end
end)
