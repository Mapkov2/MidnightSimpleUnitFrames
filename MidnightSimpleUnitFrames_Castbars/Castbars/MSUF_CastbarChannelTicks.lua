-- Castbars/MSUF_CastbarChannelTicks.lua
-- Event-driven, spell-aware channel tick markers for the Player castbar.
-- Unknown channels retain the legacy five-marker layout; custom positions
-- remain authoritative when enabled.

local DEFAULT_MARKER_COUNT = 5
local MAX_CUSTOM_MARKER_COUNT = 10
local MAX_AUTO_TICK_COUNT = 12

-- Fixed counts retain their number of ticks under haste. Interval entries
-- derive their tick count from the channel duration captured at channel start.
local CHANNEL_TICK_DATA = {
    -- Evoker
    [356995] = { ticks = 4, modSpell = 1219723, modTicks = 5 }, -- Disintegrate / Azure Celerity
    -- Priest
    [15407] = { ticks = 6 }, -- Mind Flay
    [48045] = { ticks = 6 }, -- Mind Sear
    [64843] = { ticks = 4 }, -- Divine Hymn
    [47757] = { ticks = 3 }, -- Penance (Heal)
    [47758] = { ticks = 3 }, -- Penance (Damage)
    [373129] = { ticks = 3 }, -- Dark Reprimand (Damage)
    [400171] = { ticks = 3 }, -- Dark Reprimand (Heal)
    -- Mage
    [5143] = { ticks = 5 }, -- Arcane Missiles
    [12051] = { ticks = 6 }, -- Evocation
    [205021] = { ticks = 5 }, -- Ray of Frost
    -- Druid
    [740] = { ticks = 4 }, -- Tranquility
    -- Demon Hunter
    [198013] = { tickInterval = 0.2 }, -- Eye Beam
    [473728] = { tickInterval = 0.2 }, -- Void Ray
    [212084] = { ticks = 10 }, -- Fel Devastation
    -- Warlock
    [198590] = { ticks = 5 }, -- Drain Soul
    [755] = { ticks = 5 }, -- Health Funnel
    [234153] = { ticks = 5 }, -- Drain Life
    -- Death Knight
    [206931] = { ticks = 3 }, -- Blooddrinker
    -- Monk
    [113656] = { ticks = 4 }, -- Fists of Fury
    [115175] = { ticks = 12 }, -- Soothing Mist
    [443028] = { ticks = 4 }, -- Celestial Conduit
    -- Racial
    [291944] = { ticks = 6 }, -- Regeneratin'
}

local issecretvalue = _G.issecretvalue or function() return false end
local IsPlayerSpell = _G.IsPlayerSpell

local function PlainNumber(value)
    if issecretvalue(value) == true or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function ActiveSpellID(frame)
    return PlainNumber(frame and frame._msufActiveSpellID)
end

local function ChannelDurationSeconds(frame)
    local duration = PlainNumber(frame and frame._msufPlainTotal)
    return duration and duration > 0 and duration or nil
end

local function PlayerKnowsSpell(spellID)
    if type(IsPlayerSpell) ~= "function" then return false end
    local ok, known = pcall(IsPlayerSpell, spellID)
    return ok and issecretvalue(known) ~= true and known == true
end

local function AutomaticMarkerLayout(frame)
    local tickData = CHANNEL_TICK_DATA[ActiveSpellID(frame)]
    if not tickData then
        return DEFAULT_MARKER_COUNT, DEFAULT_MARKER_COUNT + 1
    end

    local tickCount
    if tickData.tickInterval then
        local duration = ChannelDurationSeconds(frame)
        if duration then
            tickCount = math.floor((duration / tickData.tickInterval) + 0.0001)
        end
    else
        tickCount = tickData.ticks
        if tickData.modSpell and tickData.modTicks and PlayerKnowsSpell(tickData.modSpell) then
            tickCount = tickData.modTicks
        end
    end

    tickCount = PlainNumber(tickCount)
    if not tickCount then
        return DEFAULT_MARKER_COUNT, DEFAULT_MARKER_COUNT + 1
    end

    tickCount = math.floor(tickCount + 0.5)
    if tickCount < 1 then tickCount = 1 end
    if tickCount > MAX_AUTO_TICK_COUNT then tickCount = MAX_AUTO_TICK_COUNT end
    return math.max(0, tickCount - 1), tickCount
end

local function TickConfig(frame)
    local db = MSUF_DB
    local general = db and db.general
    local playerCastbar = db and db.player and db.player.castbar
    if not (general and general.castbarShowChannelTicks == true) then
        return false, 0, nil, false
    end

    if not (playerCastbar and playerCastbar.channelTickUseCustom == true) then
        local markerCount, divisor = AutomaticMarkerLayout(frame)
        return markerCount > 0, markerCount, nil, false, divisor
    end

    local markerCount = tonumber(playerCastbar.channelTickCount) or DEFAULT_MARKER_COUNT
    if markerCount ~= markerCount or markerCount == math.huge or markerCount == -math.huge then
        markerCount = DEFAULT_MARKER_COUNT
    end
    markerCount = math.floor(markerCount + 0.5)
    if markerCount < 0 then
        markerCount = 0
    elseif markerCount > MAX_CUSTOM_MARKER_COUNT then
        markerCount = MAX_CUSTOM_MARKER_COUNT
    end
    return markerCount > 0, markerCount, playerCastbar.channelTickPosPct, true, markerCount + 1
end

local function MSUF_IsChannelTickLinesEnabled()
    local enabled = TickConfig()
    return enabled == true
end

local MSUF_PlayerChannelHasteMarkers_Update

local function MSUF_PlayerChannelHasteMarkers_Ensure(self, markerCount)
    if not (self and self.unit == "player") then return end
    local sb = self.statusBar
    if not (sb and sb.CreateTexture) then return end

    local stripes = self._msufPlayerChannelHasteMarkers
    if not stripes then
        stripes = {}
        self._msufPlayerChannelHasteMarkers = stripes
    end

    markerCount = markerCount or DEFAULT_MARKER_COUNT
    for i = 1, markerCount do
        if not stripes[i] then
            local t = sb:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(1, 1, 1, 1)
            if t.SetAlpha then t:SetAlpha(1) end
            t:SetWidth(2)
            t:SetPoint("TOP", sb, "TOP", 0, 0)
            t:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
            t:Hide()
            stripes[i] = t
        end
    end

    -- Keep markers aligned if the castbar is resized (Edit Mode, scale changes, etc.)
    if not self._msufPlayerChannelHasteMarkersHooked and sb.HookScript then
        self._msufPlayerChannelHasteMarkersHooked = true
        sb:HookScript("OnSizeChanged", function()
            if self and self._msufPlayerChannelTickRuntimeActive == true and MSUF_PlayerChannelHasteMarkers_Update then
                MSUF_PlayerChannelHasteMarkers_Update(self, true)
            end
        end)
    end
end

local function HideExtraMarkers(self, firstHiddenIndex)
    local stripes = self and self._msufPlayerChannelHasteMarkers
    if not stripes then return end
    for i = firstHiddenIndex, #stripes do
        local t = stripes[i]
        if t and t.Hide then t:Hide() end
    end
end

local function MSUF_PlayerChannelHasteMarkers_Hide(self)
    local stripes = self and self._msufPlayerChannelHasteMarkers
    if not stripes then return end
    for i = 1, #stripes do
        local t = stripes[i]
        if t and t.Hide then t:Hide() end
    end
    if self then
        self._msufPlayerChannelHasteMarkersLastW = nil
        self._msufPlayerChannelHasteMarkersLastF = nil
        self._msufPlayerChannelTickRuntimeActive = nil
    end
end

MSUF_PlayerChannelHasteMarkers_Update = function(self, force)
    if not (self and self.unit == "player") then return end

    -- Only for channels; never for empower.
    if not (self.MSUF_isChanneled and not self.isEmpower) then
        MSUF_PlayerChannelHasteMarkers_Hide(self)
        return
    end

    local enabled, markerCount, customPositions, useCustom, divisor = TickConfig(self)
    self._msufPlayerChannelTickRuntimeActive = enabled and true or nil
    if not enabled then
        MSUF_PlayerChannelHasteMarkers_Hide(self)
        return
    end

    local sb = self.statusBar
    if not (sb and sb.GetWidth) then return end

    MSUF_PlayerChannelHasteMarkers_Ensure(self, markerCount)
    local stripes = self._msufPlayerChannelHasteMarkers
    if not stripes then return end

    local w = sb:GetWidth() or 0
    if w <= 1 then
        -- The size hook performs the exact reposition when layout becomes valid.
        w = self._msufPlayerChannelHasteMarkersLastW or 200
    end

    local lastW = self._msufPlayerChannelHasteMarkersLastW
    if not force and lastW == w then
        -- no change, keep
    else
        self._msufPlayerChannelHasteMarkersLastW = w
        self._msufPlayerChannelHasteMarkersLastF = nil

        local rf = (self._msufStripeReverseFill == true)

        divisor = divisor or (markerCount + 1)
        for i = 1, markerCount do
            local t = stripes[i]
            if t and t.SetPoint then
                if t.SetAlpha then t:SetAlpha(1) end

                local x
                if useCustom and type(customPositions) == "table" and type(customPositions[i]) == "number" then
                    local pct = customPositions[i]
                    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
                    x = w * (pct / 100)
                else
                    local fraction = i / divisor
                    if fraction < 0.02 then fraction = 0.02 elseif fraction > 0.98 then fraction = 0.98 end
                    x = w * fraction
                end

                t:ClearAllPoints()
                if rf then
                    t:SetPoint("TOP", sb, "TOPRIGHT", -x, 0)
                    t:SetPoint("BOTTOM", sb, "BOTTOMRIGHT", -x, 0)
                else
                    t:SetPoint("TOP", sb, "TOPLEFT", x, 0)
                    t:SetPoint("BOTTOM", sb, "BOTTOMLEFT", x, 0)
                end
            end
        end
        HideExtraMarkers(self, markerCount + 1)
    end

    -- Always visible during the entire channel.
    for i = 1, markerCount do
        local t = stripes[i]
        if t then
            if t.SetAlpha then t:SetAlpha(1) end
            if t.Show then t:Show() end
        end
    end
end


-- Export: Options can call this to apply immediately (overrides core LoD stub).
function _G.MSUF_UpdateCastbarChannelTicks()
    local function Apply(frame)
        if not frame then return end
        MSUF_PlayerChannelHasteMarkers_Update(frame, true)
    end

    -- Real + preview (Edit Mode)
    Apply(_G.MSUF_PlayerCastbar)
    Apply(_G.MSUF_PlayerCastbarPreview)
end

-- Replace the core LoD stub's legacy custom-only renderer once the real
-- Castbars addon is loaded. This keeps automatic and custom markers on one
-- texture pool and prevents duplicate lines.
_G.MSUF_ApplyPlayerChannelTickMarkers = _G.MSUF_UpdateCastbarChannelTicks



-- Vehicle support: while in a vehicle, some casts/channels are reported on unit "vehicle" instead of "player".
-- Keep frame.unit as "player" for options/anchoring, but query the effective unit for cast APIs.

---------------------------------------------------------------------------
-- _G exports
---------------------------------------------------------------------------
_G.MSUF_IsChannelTickLinesEnabled          = MSUF_IsChannelTickLinesEnabled
_G.MSUF_PlayerChannelHasteMarkers_Update   = MSUF_PlayerChannelHasteMarkers_Update
_G.MSUF_PlayerChannelHasteMarkers_Hide     = MSUF_PlayerChannelHasteMarkers_Hide
_G.MSUF_PlayerChannelHasteMarkers_Ensure   = MSUF_PlayerChannelHasteMarkers_Ensure
