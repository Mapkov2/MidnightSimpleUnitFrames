local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua
--- Enemy arena trinket display shared by Retail and supported Classic clients.
---
--- Retail 12.x keeps enemy cooldown numbers secret. Its provider therefore
--- feeds C_PvP's DurationObject directly into the Cooldown widget and relays
--- Blizzard's authoritative CcRemoverFrame texture without reading it back.
--- Classic uses the public millisecond values from GetArenaCrowdControlInfo.
--- Mists additionally has a narrow combat-log fallback for the PvP trinket
--- spell because ARENA_COOLDOWNS_UPDATE is not reliable on that client. The
--- combat log is subscribed only while the player is inside an arena instance.
---
--- Size, side, offset and layer come from MSUF_DB.arena (trinket* keys). One
--- resolver (TrinketLayout) serves the live holders, the arena frame preview of
--- the menu and Edit Mode (which shows these same holders) and the menu's unit
--- preview. Settings reach the holders on the cold path only: a unit-frame apply
--- bumps the layout serial and the next position pass re-applies it.
---
--- All work is event-driven. There is no OnUpdate, ticker, or polling loop.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local type = type
local tonumber = tonumber
-- arena1..N (N = MSUF.Client.MaxArenaOpponents: 3 on Mainline, 5 on TBC/Mists).
-- Game/Shared/Initialize.lua publishes it as MSUF_MAX_ARENA_FRAMES; clamp it to
-- 0..5 and fall back to 3 when the client initializer did not run.
local MAX_ARENA = math.max(0, math.min(5, math.floor(tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3)))
local RETAIL_TRINKET_TEXTURE = 1322720 -- inv_jewelry_trinketpvp_01
local CLASSIC_TRINKET_TEXTURE = 133453 -- inv_jewelry_trinketpvp_02
local MISTS_TRINKET_SPELL_ID = 42292
local MISTS_TRINKET_DURATION = 120

local Client = MSUF.Client or {}
-- Every suffixed TOC (Mainline, TBC, Mists, Vanilla) loads
-- Game/Shared/Initialize.lua before this file, so Client.IsRetail is set.
local IS_RETAIL = Client.IsRetail == true
local IS_MISTS = Client.IsMists == true
local FALLBACK_TEXTURE = IS_RETAIL and RETAIL_TRINKET_TEXTURE or CLASSIC_TRINKET_TEXTURE

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

-- The factory look: a 20 px icon 4 px right of the arena frame, on a layer
-- above every default layer of the arena frame (custom aura containers sit on
-- 9), so the icon still draws over the frame like the old MEDIUM-strata holder.
local TRINKET_DEFAULTS = { size = 20, anchor = "RIGHT", x = 4, y = 0, layer = 10 }
local TRINKET_LIMITS = { sizeMin = 10, sizeMax = 64, offset = 200 }
-- Frame side -> holder point, arena frame point.
local TRINKET_SIDES = {
    RIGHT = { "LEFT", "RIGHT" },
    LEFT = { "RIGHT", "LEFT" },
    TOP = { "BOTTOM", "TOP" },
    BOTTOM = { "TOP", "BOTTOM" },
}
-- The preview sample: a trinket used 42 seconds ago on its 2 minute cooldown.
local PREVIEW_COOLDOWN, PREVIEW_ELAPSED = 120, 42

local holders = {}
local requested = {}
local relaySources = {}
local mistsFallback = {}
local RefreshCooldown
local SyncMistsCombatLog
-- Bumped by every settings apply; a holder re-applies its layout when its
-- stamp differs, so the per-event position pass stays a comparison.
local layoutSerial = 1
-- Arena frames the menu or Edit Mode preview forced at its last sync.
local previewSlots = 0

local function ArenaConf()
    local db = _G.MSUF_DB
    return db and db.arena or nil
end

local function WholeNumber(value, fallback, low, high)
    value = tonumber(value)
    if value == nil or value ~= value then return fallback end
    value = math.floor(value + 0.5)
    if value < low then return low end
    if value > high then return high end
    return value
end

--- The trinket layout from the profile: size, holder point, arena frame point,
--- x, y and the 0-30 layer. The runtime and every preview read this.
local NO_CONF = {}
local function TrinketLayout()
    local conf = ArenaConf() or NO_CONF
    local side = TRINKET_SIDES[conf.trinketAnchor] or TRINKET_SIDES[TRINKET_DEFAULTS.anchor]
    local limit = TRINKET_LIMITS.offset
    return WholeNumber(conf.trinketSize, TRINKET_DEFAULTS.size, TRINKET_LIMITS.sizeMin, TRINKET_LIMITS.sizeMax),
        side[1], side[2],
        WholeNumber(conf.trinketOffsetX, TRINKET_DEFAULTS.x, -limit, limit),
        WholeNumber(conf.trinketOffsetY, TRINKET_DEFAULTS.y, -limit, limit),
        WholeNumber(conf.trinketLayer, TRINKET_DEFAULTS.layer, 0, 30)
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
        local getState = pvp.GetActiveMatchState
        local states = _G.Enum and _G.Enum.PvPMatchState
        local engaged = states and states.Engaged
        return (type(active) == "function" and active() == true)
            or (type(complete) == "function" and complete() == true)
            or (engaged ~= nil and type(getState) == "function" and getState() == engaged)
    end

    local isInInstance = _G.IsInInstance
    if type(isInInstance) ~= "function" then return false end
    local _, instanceType = isInInstance()
    return instanceType == "arena"
end

local function EnsureHolder(index)
    local holder = holders[index]
    if holder then return holder end

    holder = PixelLayoutRegion(CreateFrame("Frame", "MSUF_ArenaTrinket" .. index, UIParent))
    holder:SetSize(20, 20)
    holder:SetFrameStrata("MEDIUM")
    holder:Hide()

    holder.icon = PixelLayoutRegion(holder:CreateTexture(nil, "ARTWORK"))
    holder.icon:SetAllPoints(holder)
    holder.icon:SetTexture(FALLBACK_TEXTURE)
    holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    holder.cooldown = PixelLayoutRegion(CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate"))
    holder.cooldown:SetAllPoints(holder)
    holder.cooldown:SetDrawEdge(false)

    holders[index] = holder
    return holder
end

--- Cold path: size, anchor, strata and level of one holder. The holder takes
--- the arena frame's strata, so its 0-30 layer orders it against the frame's
--- own elements on the shared MSUF scale (as the castbar does).
local function ApplyHolderLayout(holder, frame)
    local size, point, relativePoint, x, y, layer = TrinketLayout()
    holder:ClearAllPoints()
    holder:SetPoint(point, frame, relativePoint, x, y)
    holder:SetSize(size, size)
    local layers = MSUF.UF.Layers
    holder:SetFrameStrata(layers.ParentStrata(frame) or "MEDIUM")
    local level = layers.ElementLevel(layer, TRINKET_DEFAULTS.layer, 0)
    holder:SetFrameLevel(level)
    holder.cooldown:SetFrameLevel(level + 1)
    holder._msufTrinketAnchor = frame
    holder._msufTrinketSerial = layoutSerial
end

local function PositionHolder(holder, index)
    local frame = ArenaFrame(index)
    if not frame then return false end
    -- The anchor is relative to the arena frame, so it follows the frame by
    -- itself; only a different frame object or a settings apply re-anchors.
    if holder._msufTrinketAnchor ~= frame or holder._msufTrinketSerial ~= layoutSerial then
        ApplyHolderLayout(holder, frame)
    end
    return true
end

local function PreviewForced(index)
    local frame = ArenaFrame(index)
    return frame ~= nil and frame._msufArenaPreviewForced == true
end

-- A preview holder shows the stock trinket icon with a sample swipe; the
-- native Cooldown animates it, so the preview adds no update loop either.
local function ShowPreviewHolder(holder)
    if holder._msufTrinketPreview ~= true then
        holder._msufTrinketPreview = true
        holder.spellID = nil
        holder.icon:SetTexture(FALLBACK_TEXTURE)
        holder.cooldown:SetCooldown(GetTime() - PREVIEW_ELAPSED, PREVIEW_COOLDOWN)
    end
    holder:Show()
end

local function EndPreview(holder)
    if holder._msufTrinketPreview ~= true then return end
    holder._msufTrinketPreview = nil
    holder.cooldown:Clear()
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
    local active
    if IS_MISTS then
        -- The combat-log fallback follows the arena instance, not the display
        -- settings, so the instance is read once here for both.
        local inArena = InArenaMatch()
        SyncMistsCombatLog(inArena)
        active = inArena and ArenaEnabled() and ShowTrinketEnabled()
    else
        active = ArenaEnabled() and ShowTrinketEnabled() and InArenaMatch()
    end
    -- Outside a menu or Edit Mode preview this stays one number comparison.
    local preview = previewSlots > 0 and ArenaEnabled() and ShowTrinketEnabled()
    for index = 1, MAX_ARENA do
        local unit = "arena" .. index
        local holder = EnsureHolder(index)
        AttachRetailRelay(index, holder)

        local wanted = active and LiveUnitExists(unit)
        if wanted and PositionHolder(holder, index) then
            EndPreview(holder)
            holder:Show()
            if allowRequest and not requested[index] then
                local request = _G.C_PvP and _G.C_PvP.RequestCrowdControlSpell
                if type(request) == "function" then
                    requested[index] = true
                    request(unit)
                end
            end
            RefreshCooldown(holder, index)
        elseif preview and PreviewForced(index) and PositionHolder(holder, index) then
            requested[index] = nil
            ShowPreviewHolder(holder)
        else
            requested[index] = nil
            EndPreview(holder)
            holder:Hide()
        end
    end
end

--- Called by the arena frame preview owner (LoadConditions) after it forced or
--- released the arena frames: the menu's Arena page and MSUF Edit Mode. The
--- preview shows these same holders, so it is the runtime geometry 1:1.
local function SyncTrinketPreview()
    local count = 0
    for index = 1, MAX_ARENA do
        if PreviewForced(index) then count = count + 1 end
    end
    if count == 0 and previewSlots == 0 then return end
    previewSlots = count
    SyncTrinketIcons(false)
end

--- Cold path for settings changes: unit-frame applies of the arena scope (menu
--- edits, section reset, undo, profile switch and import) land here. The serial
--- re-applies layout on the next position pass; the sync shows it at once and
--- follows the show switch.
local function RefreshTrinketLayout(configKey)
    if configKey ~= nil and tostring(configKey):sub(1, 5) ~= "arena" then return end
    layoutSerial = layoutSerial + 1
    SyncTrinketIcons(false)
end

local function ResetSlot(index)
    requested[index] = nil
    mistsFallback[index] = nil
    local holder = holders[index]
    if not holder then return end
    holder.spellID = nil
    holder._msufTrinketPreview = nil
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
    -- SyncMistsCombatLog delivers this event inside arena instances only, so the
    -- per-event path does not ask the client for the instance type again.
    if not IS_MISTS or not ArenaEnabled() or not ShowTrinketEnabled() then return end
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
    if event == "PLAYER_LOGIN" then
        -- The first sync reads the arena switches, so it waits for the
        -- SavedVariables; it attaches the Retail texture relays before the
        -- first arena response. World/opponent events retry later.
        SyncTrinketIcons(false)
        return
    end
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
local mistsLogWired = false
local mistsLogLive = false

--- Mists only. The combat-log fallback is subscribed while the player is inside
--- an arena instance and released when the player leaves, so raids and the open
--- world never deliver a combat-log event to this module. SyncTrinketIcons calls
--- this from PLAYER_ENTERING_WORLD and every arena event; the live flag keeps
--- those repeat calls comparison-only.
SyncMistsCombatLog = function(wanted)
    if not mistsLogWired or wanted == mistsLogLive then return end
    if eventFrame then
        if wanted then
            eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        else
            eventFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end
    elseif wanted then
        local register = _G.MSUF_EventBus_Register
        if type(register) ~= "function" then return end
        register("COMBAT_LOG_EVENT_UNFILTERED", "MSUF_ARENA_TRINKET_MISTS_LOG", HandleEvent)
    else
        local unregister = _G.MSUF_EventBus_Unregister
        if type(unregister) ~= "function" then return end
        unregister("COMBAT_LOG_EVENT_UNFILTERED", "MSUF_ARENA_TRINKET_MISTS_LOG")
    end
    mistsLogLive = wanted
end

local function WireEvents()
    local events = {
        { "ARENA_OPPONENT_UPDATE", "MSUF_ARENA_TRINKET_OPPONENT" },
        { "ARENA_CROWD_CONTROL_SPELL_UPDATE", "MSUF_ARENA_TRINKET_SPELL" },
        { "ARENA_COOLDOWNS_UPDATE", "MSUF_ARENA_TRINKET_COOLDOWN" },
        { "PLAYER_ENTERING_WORLD", "MSUF_ARENA_TRINKET_WORLD" },
        { "PLAYER_LOGIN", "MSUF_ARENA_TRINKET_LOGIN" },
    }
    if IS_RETAIL then
        events[#events + 1] = { "PVP_MATCH_STATE_CHANGED", "MSUF_ARENA_TRINKET_MATCH" }
    end
    -- COMBAT_LOG_EVENT_UNFILTERED is deliberately absent: on Mists
    -- SyncMistsCombatLog owns that subscription per arena instance.
    mistsLogWired = IS_MISTS

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

-- Defensive: Client.UnsupportedUnits marks arena absent on Classic Era, whose
-- TOC still loads this module. The trinket export stays, but no arena event is
-- subscribed and no relay is attached there.
if not (type(Client.SupportsUnit) == "function" and Client.SupportsUnit("arena1") == false) then
    WireEvents()
end

ExportPublic("MSUF_ArenaMatch_SyncTrinketIcons", function()
    SyncTrinketIcons(true)
end)
ExportPublic("MSUF_ArenaTrinkets_SyncPreview", SyncTrinketPreview)
ExportPublic("MSUF_ArenaTrinkets_RefreshLayout", RefreshTrinketLayout)

--- Read-only surface for the menu (unit preview, PvP Trinket section, Layer
--- Overview) and the Edit Mode mover: the resolver, the factory values the
--- runtime itself uses and the holder of an arena slot.
MSUF.ArenaTrinkets = {
    Layout = TrinketLayout,
    Shown = function() return ArenaEnabled() and ShowTrinketEnabled() end,
    Holder = function(index) return holders[index] end,
    DEFAULTS = TRINKET_DEFAULTS,
    LIMITS = TRINKET_LIMITS,
    FallbackTexture = FALLBACK_TEXTURE,
}
