--- Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua
--- Enemy arena trinket display shared by Retail and supported Classic clients.
---
--- Retail 12.x keeps enemy cooldown numbers secret. Its provider therefore
--- feeds C_PvP's DurationObject directly into the Cooldown widget and relays
--- Blizzard's authoritative CcRemoverFrame texture without reading it back.
--- Classic uses the public millisecond values from GetArenaCrowdControlInfo.
--- Mists additionally has a narrow combat-log fallback for the PvP trinket
--- spell because ARENA_COOLDOWNS_UPDATE is not reliable on that client.
---
--- All work is event-driven. There is no OnUpdate, ticker, or polling loop.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local type = type
local tonumber = tonumber
local MAX_ARENA = 3
local RETAIL_TRINKET_TEXTURE = 1322720 -- inv_jewelry_trinketpvp_01
local CLASSIC_TRINKET_TEXTURE = 133453 -- inv_jewelry_trinketpvp_02
local MISTS_TRINKET_SPELL_ID = 42292
local MISTS_TRINKET_DURATION = 120

local Client = MSUF.Client or {}
-- The canonical Retail TOC does not load Game/Shared/Initialize.lua. Prefer its
-- flag when present, but derive Mainline directly when this shared feature is
-- loaded by that TOC so Retail can never fall into the numeric Classic path.
local IS_RETAIL = Client.IsRetail == true
if Client.IsRetail == nil then
    local projectID = _G.WOW_PROJECT_ID
    local mainlineID = _G.WOW_PROJECT_MAINLINE
    IS_RETAIL = mainlineID ~= nil and projectID == mainlineID
end
local IS_MISTS = Client.IsMists == true
local FALLBACK_TEXTURE = IS_RETAIL and RETAIL_TRINKET_TEXTURE or CLASSIC_TRINKET_TEXTURE

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local holders = {}
local requested = {}
local relaySources = {}
local mistsFallback = {}
local RefreshCooldown

local function ArenaConf()
    local db = _G.MSUF_DB
    return db and db.arena or nil
end

local function ArenaEnabled()
    local conf = ArenaConf()
    return not conf or conf.enabled ~= false
end

local function ShowTrinketEnabled()
    local conf = ArenaConf()
    return not conf or conf.showTrinket ~= false
end

local function ArenaFrame(index)
    local uf = MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame("arena" .. index)
        if frame then return frame end
    end
    local frames = uf and uf.frames
    return (frames and frames["arena" .. index]) or _G["MSUF_arena" .. index]
end

local function IsSecret(value)
    local issecret = _G.issecretvalue
    return type(issecret) == "function" and issecret(value) == true
end

local function LiveUnitExists(unit)
    local secrets = MSUF.Secrets
    local existsPlain = secrets and secrets.UnitExistsPlain
    if type(existsPlain) == "function" then
        return existsPlain(unit) == true
    end
    local exists = _G.UnitExists
    return type(exists) == "function" and exists(unit) == true
end

local function InArenaMatch()
    if IS_RETAIL then
        local pvp = _G.C_PvP
        local considered = pvp and pvp.IsMatchConsideredArena
        if type(considered) ~= "function" or considered() ~= true then return false end
        local active = pvp.IsMatchActive
        local complete = pvp.IsMatchComplete
        local engaged = pvp.IsMatchEngaged
        return (type(active) == "function" and active() == true)
            or (type(complete) == "function" and complete() == true)
            or (type(engaged) == "function" and engaged() == true)
    end

    local isInInstance = _G.IsInInstance
    if type(isInInstance) ~= "function" then return false end
    local _, instanceType = isInInstance()
    return instanceType == "arena"
end

local function EnsureHolder(index)
    local holder = holders[index]
    if holder then return holder end

    holder = CreateFrame("Frame", "MSUF_ArenaTrinket" .. index, UIParent)
    holder:SetSize(20, 20)
    holder:SetFrameStrata("MEDIUM")
    holder:Hide()

    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetAllPoints(holder)
    holder.icon:SetTexture(FALLBACK_TEXTURE)
    holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    holder.cooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    holder.cooldown:SetAllPoints(holder)
    holder.cooldown:SetDrawEdge(false)

    holders[index] = holder
    return holder
end

local function PositionHolder(holder, index)
    local frame = ArenaFrame(index)
    if not frame then return false end
    holder:ClearAllPoints()
    holder:SetPoint("LEFT", frame, "RIGHT", 4, 0)
    return true
end

local function ApplyTexture(holder, texture)
    if not holder or not holder.icon then return end
    if IsSecret(texture) then
        -- Texture widgets accept Blizzard's secret texture value. Do not
        -- compare, stringify, or otherwise inspect it in addon code.
        holder.icon:SetTexture(texture)
    elseif texture then
        holder.icon:SetTexture(texture)
    else
        holder.icon:SetTexture(FALLBACK_TEXTURE)
    end
end

local function ClassicSpellTexture(spellID, itemID)
    if itemID and itemID ~= 0 then
        local getItemIcon = _G.C_Item and _G.C_Item.GetItemIconByID
        if type(getItemIcon) == "function" then
            local texture = getItemIcon(itemID)
            if texture then return texture end
        end
        getItemIcon = _G.GetItemIcon
        if type(getItemIcon) == "function" then
            local texture = getItemIcon(itemID)
            if texture then return texture end
        end
    end

    local getSpellTexture = _G.GetSpellTexture
    if type(getSpellTexture) == "function" then
        local texture, textureNoOverride = getSpellTexture(spellID)
        return textureNoOverride or texture
    end
    getSpellTexture = _G.C_Spell and _G.C_Spell.GetSpellTexture
    return type(getSpellTexture) == "function" and getSpellTexture(spellID) or nil
end

local function ActiveMistsFallback(index)
    local fallback = mistsFallback[index]
    if not fallback then return nil end
    local getTime = _G.GetTime
    local now = type(getTime) == "function" and getTime() or 0
    if now < fallback.startTime + fallback.duration then return fallback end
    mistsFallback[index] = nil
    return nil
end

local function ApplyMistsFallback(holder, index)
    local fallback = ActiveMistsFallback(index)
    if not fallback then return false end
    holder.cooldown:SetCooldown(fallback.startTime, fallback.duration)
    return true
end

local function RefreshRetailCooldown(holder, index)
    local cooldown = holder and holder.cooldown
    if not cooldown then return end
    local pvp = _G.C_PvP

    -- Preferred Midnight path: DurationObject flows directly from Blizzard to
    -- the native Cooldown widget without exposing or comparing secret numbers.
    local getDuration = pvp and pvp.GetArenaCrowdControlDuration
    if type(getDuration) == "function" and type(cooldown.SetCooldownFromDurationObject) == "function" then
        local duration = getDuration("arena" .. index)
        if duration ~= nil then
            cooldown:SetCooldownFromDurationObject(duration)
            return
        end
    end

    -- Non-secret fallback for older Retail/spectator contexts.
    local getInfo = pvp and pvp.GetArenaCrowdControlInfo
    if type(getInfo) ~= "function" then return end
    local spellID, startTimeMs, durationMs = getInfo("arena" .. index)
    if IsSecret(spellID) or IsSecret(startTimeMs) or IsSecret(durationMs) then return end

    local duration = (tonumber(durationMs) or 0) / 1000
    if spellID and duration > 0 then
        cooldown:SetCooldown((tonumber(startTimeMs) or 0) / 1000, duration)
        local getTexture = _G.C_Spell and _G.C_Spell.GetSpellTexture
        if type(getTexture) == "function" then ApplyTexture(holder, getTexture(spellID)) end
    else
        cooldown:Clear()
    end
end

local function RefreshClassicCooldown(holder, index)
    local cooldown = holder and holder.cooldown
    if not cooldown then return end
    local getInfo = _G.C_PvP and _G.C_PvP.GetArenaCrowdControlInfo
    if type(getInfo) ~= "function" then
        if not ApplyMistsFallback(holder, index) then cooldown:Clear() end
        return
    end

    local spellID, itemID, startTimeMs, durationMs = getInfo("arena" .. index)
    if IsSecret(spellID) or IsSecret(itemID) or IsSecret(startTimeMs) or IsSecret(durationMs) then
        if not ApplyMistsFallback(holder, index) then cooldown:Clear() end
        return
    end
    local numericSpellID = tonumber(spellID)
    if numericSpellID and numericSpellID > 0 then
        holder.spellID = numericSpellID
        ApplyTexture(holder, ClassicSpellTexture(numericSpellID, tonumber(itemID)))

        local duration = (tonumber(durationMs) or 0) / 1000
        if duration > 0 then
            mistsFallback[index] = nil
            cooldown:SetCooldown((tonumber(startTimeMs) or 0) / 1000, duration)
            return
        end
    end

    if not ApplyMistsFallback(holder, index) then cooldown:Clear() end
end

RefreshCooldown = function(holder, index)
    if IS_RETAIL then
        RefreshRetailCooldown(holder, index)
    else
        RefreshClassicCooldown(holder, index)
    end
end

local function AttachRetailRelay(index, holder)
    if not IS_RETAIL or not holder then return end
    local member = _G["CompactArenaFrameMember" .. index]
    local ccRemover = member and member.CcRemoverFrame
    if not ccRemover or relaySources[index] == ccRemover then return end

    local hook = _G.hooksecurefunc
    if type(hook) ~= "function" then return end

    if ccRemover.Icon and type(ccRemover.Icon.SetTexture) == "function" then
        hook(ccRemover.Icon, "SetTexture", function(_, texture)
            ApplyTexture(holder, texture)
        end)
    end
    if ccRemover.Cooldown and type(ccRemover.Cooldown.SetCooldown) == "function" then
        hook(ccRemover.Cooldown, "SetCooldown", function()
            RefreshRetailCooldown(holder, index)
        end)
    end
    if ccRemover.Cooldown and type(ccRemover.Cooldown.Clear) == "function" then
        hook(ccRemover.Cooldown, "Clear", function()
            holder.cooldown:Clear()
        end)
    end

    -- Unlike older arena addons, MSUF leaves the Blizzard object parented to
    -- its native owner. The hooks relay state only and do not move protected UI.
    relaySources[index] = ccRemover
end

-- One request per visible slot segment. Response events refresh delivered data
-- only; they never request again, avoiding request -> response feedback loops.
local function SyncTrinketIcons(allowRequest)
    local active = ArenaEnabled() and ShowTrinketEnabled() and InArenaMatch()
    for index = 1, MAX_ARENA do
        local unit = "arena" .. index
        local holder = EnsureHolder(index)
        AttachRetailRelay(index, holder)

        local wanted = active and LiveUnitExists(unit)
        if wanted and PositionHolder(holder, index) then
            holder:Show()
            if allowRequest and not requested[index] then
                local request = _G.C_PvP and _G.C_PvP.RequestCrowdControlSpell
                if type(request) == "function" then
                    requested[index] = true
                    request(unit)
                end
            end
            RefreshCooldown(holder, index)
        else
            requested[index] = nil
            holder:Hide()
        end
    end
end

local function ResetSlot(index)
    requested[index] = nil
    mistsFallback[index] = nil
    local holder = holders[index]
    if not holder then return end
    holder.spellID = nil
    holder.cooldown:Clear()
    ApplyTexture(holder, nil)
    holder:Hide()
end

local function UnitIndex(unit)
    if IsSecret(unit) or type(unit) ~= "string" then return nil end
    local index = tonumber(unit:match("^arena(%d+)$"))
    return index and index >= 1 and index <= MAX_ARENA and index or nil
end

local function HandleClassicSpellUpdate(unit, spellID, itemID)
    if IS_RETAIL then return end
    local index = UnitIndex(unit)
    if not index then return end
    local holder = EnsureHolder(index)
    if IsSecret(spellID) or IsSecret(itemID) then
        -- Some client/event combinations publish restricted numeric payloads.
        -- They must not enter tonumber, ordering, table keys, or texture APIs.
        RefreshClassicCooldown(holder, index)
        return
    end
    local numericSpellID = tonumber(spellID)
    if numericSpellID and numericSpellID > 0 then
        holder.spellID = numericSpellID
        ApplyTexture(holder, ClassicSpellTexture(numericSpellID, tonumber(itemID)))
    else
        holder.spellID = nil
        ApplyTexture(holder, nil)
    end
    RefreshClassicCooldown(holder, index)
end

local function HandleMistsCombatLog()
    if not IS_MISTS or not ArenaEnabled() or not ShowTrinketEnabled() or not InArenaMatch() then return end
    local getInfo = _G.CombatLogGetCurrentEventInfo
    if type(getInfo) ~= "function" then return end
    local _, subEvent, _, sourceGUID, _, _, _, _, _, _, _, spellID = getInfo()
    if subEvent ~= "SPELL_CAST_SUCCESS" or spellID ~= MISTS_TRINKET_SPELL_ID then return end

    local unitGUID = _G.UnitGUID
    if type(unitGUID) ~= "function" then return end
    for index = 1, MAX_ARENA do
        local unit = "arena" .. index
        if sourceGUID == unitGUID(unit) then
            local getTime = _G.GetTime
            local startTime = type(getTime) == "function" and getTime() or 0
            mistsFallback[index] = { startTime = startTime, duration = MISTS_TRINKET_DURATION }
            local holder = EnsureHolder(index)
            holder.spellID = MISTS_TRINKET_SPELL_ID
            ApplyTexture(holder, ClassicSpellTexture(MISTS_TRINKET_SPELL_ID))
            holder.cooldown:SetCooldown(startTime, MISTS_TRINKET_DURATION)
            return
        end
    end
end

local function HandleEvent(event, arg1, arg2, arg3)
    if event == "ARENA_CROWD_CONTROL_SPELL_UPDATE" then
        HandleClassicSpellUpdate(arg1, arg2, arg3)
        SyncTrinketIcons(false)
        return
    end
    if event == "ARENA_COOLDOWNS_UPDATE" then
        SyncTrinketIcons(false)
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleMistsCombatLog()
        return
    end
    if event == "ARENA_OPPONENT_UPDATE" then
        local index = UnitIndex(arg1)
        if index and (arg2 == "destroyed" or arg2 == "cleared") then ResetSlot(index) end
        SyncTrinketIcons(true)
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        for index = 1, MAX_ARENA do ResetSlot(index) end
        SyncTrinketIcons(true)
        return
    end
    if event == "PVP_MATCH_STATE_CHANGED" then
        SyncTrinketIcons(true)
    end
end

local eventFrame
local function WireEvents()
    local events = {
        { "ARENA_OPPONENT_UPDATE", "MSUF_ARENA_TRINKET_OPPONENT" },
        { "ARENA_CROWD_CONTROL_SPELL_UPDATE", "MSUF_ARENA_TRINKET_SPELL" },
        { "ARENA_COOLDOWNS_UPDATE", "MSUF_ARENA_TRINKET_COOLDOWN" },
        { "PLAYER_ENTERING_WORLD", "MSUF_ARENA_TRINKET_WORLD" },
    }
    if IS_RETAIL then
        events[#events + 1] = { "PVP_MATCH_STATE_CHANGED", "MSUF_ARENA_TRINKET_MATCH" }
    elseif IS_MISTS then
        events[#events + 1] = { "COMBAT_LOG_EVENT_UNFILTERED", "MSUF_ARENA_TRINKET_MISTS_LOG" }
    end

    local register = _G.MSUF_EventBus_Register
    if type(register) == "function" then
        for index = 1, #events do
            register(events[index][1], events[index][2], HandleEvent)
        end
        return
    end

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        HandleEvent(event, ...)
    end)
    for index = 1, #events do eventFrame:RegisterEvent(events[index][1]) end
end

WireEvents()
-- Attach Retail texture relays before the first arena response whenever the
-- native CompactArenaFrame already exists. World/opponent events retry later.
SyncTrinketIcons(false)

ExportPublic("MSUF_ArenaMatch_SyncTrinketIcons", function()
    SyncTrinketIcons(true)
end)
