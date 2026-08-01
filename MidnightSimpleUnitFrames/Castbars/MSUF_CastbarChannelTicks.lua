-- Player channel tick marker support.
-- Adds optional spell-aware channel markers to the player castbar using existing DB fields.
-- This augments castbar visuals only; cast/channel state remains in the shared runtime.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local DEFAULT_MARKER_COUNT = 5
local MAX_CUSTOM_MARKER_COUNT = 10
local MAX_AUTO_TICK_COUNT = 12

-- Fixed tick counts keep their number of ticks under haste; interval entries
-- gain ticks when the channel duration grows. Unknown channels deliberately
-- retain the legacy five-line layout instead of losing their markers.
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
    if not frame then return nil end
    local spellID = PlainNumber(frame._msufActiveSpellID)
    if spellID then return spellID end
    local state = frame._msufPlayerState
    return PlainNumber(state and state.spellId)
end

local function ChannelDurationSeconds(frame)
    local state = frame and frame._msufPlayerState
    local startTimeMS = PlainNumber(state and state.startTimeMS)
    local endTimeMS = PlainNumber(state and state.endTimeMS)
    if startTimeMS and endTimeMS and endTimeMS > startTimeMS then
        return (endTimeMS - startTimeMS) / 1000
    end

    local total = PlainNumber(frame and frame._msufPlainTotal)
    if total and total > 0 then return total end
    return nil
end

local function PlayerKnowsSpell(spellID)
    if type(IsPlayerSpell) ~= "function" then return false end
    local known = IsPlayerSpell(spellID)
    return issecretvalue(known) ~= true and known == true
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
    local general = db and db.general or nil
    local playerCastbar = db and db.player and db.player.castbar or nil

    -- The visible global switch is the authoritative on/off gate. Custom
    -- state only selects count/positions and must never override an Off write.
    if not (general and general.castbarShowChannelTicks == true) then
        return false, 0, nil, false
    end

    local useCustom = playerCastbar and playerCastbar.channelTickUseCustom == true
    if not useCustom then
        local markerCount, divisor = AutomaticMarkerLayout(frame)
        return markerCount > 0, markerCount, nil, false, divisor
    end

    local tickCount = tonumber(playerCastbar.channelTickCount) or DEFAULT_MARKER_COUNT

    if tickCount ~= tickCount or tickCount == math.huge or tickCount == -math.huge then
        tickCount = DEFAULT_MARKER_COUNT
    end
    tickCount = math.floor(tickCount + 0.5)

    if tickCount < 0 then
        tickCount = 0
    elseif tickCount > MAX_CUSTOM_MARKER_COUNT then
        tickCount = MAX_CUSTOM_MARKER_COUNT
    end

    return tickCount > 0, tickCount, playerCastbar.channelTickPosPct, true, tickCount + 1
end

local function ChannelTickLinesEnabled()
    local enabled = TickConfig()
    return enabled == true
end

local UpdatePlayerChannelHasteMarkers

local function EnsurePlayerChannelTickMarkers(frame, tickCount)
    if not (frame and frame.unit == "player") then
        return
    end

    local statusBar = frame.statusBar
    if not (statusBar and statusBar.CreateTexture) then
        return
    end

    local markers = frame._msufPlayerChannelHasteMarkers
    if not markers then
        markers = {}
        frame._msufPlayerChannelHasteMarkers = markers
    end

    tickCount = tickCount or DEFAULT_MARKER_COUNT
    for index = 1, tickCount do
        if not markers[index] then
            local marker = statusBar:CreateTexture(nil, "OVERLAY", nil, 7)
            marker:SetColorTexture(1, 1, 1, 1)

            if marker.SetAlpha then
                marker:SetAlpha(1)
            end

            marker:SetWidth(2)
            marker:SetPoint("TOP", statusBar, "TOP", 0, 0)
            marker:SetPoint("BOTTOM", statusBar, "BOTTOM", 0, 0)
            marker:Hide()
            markers[index] = marker
        end
    end

    if not frame._msufPlayerChannelHasteMarkersHooked and statusBar.HookScript then
        frame._msufPlayerChannelHasteMarkersHooked = true
        statusBar:HookScript("OnSizeChanged", function()
            if frame and frame._msufPlayerChannelTickRuntimeActive == true and UpdatePlayerChannelHasteMarkers then
                UpdatePlayerChannelHasteMarkers(frame, true)
            end
        end)
    end
end

local function HideExtraMarkers(frame, firstHiddenIndex)
    local markers = frame and frame._msufPlayerChannelHasteMarkers
    if not markers then
        return
    end

    for index = firstHiddenIndex, #markers do
        local marker = markers[index]
        if marker and marker.Hide then
            marker:Hide()
        end
    end
end

local function HidePlayerChannelTickMarkers(frame)
    local markers = frame and frame._msufPlayerChannelHasteMarkers
    if not markers then
        return
    end

    for index = 1, #markers do
        local marker = markers[index]
        if marker and marker.Hide then
            marker:Hide()
        end
    end

    if frame then
        frame._msufPlayerChannelHasteMarkersLastW = nil
        frame._msufPlayerChannelHasteMarkersLastF = nil
        frame._msufPlayerChannelTickRuntimeActive = nil
    end
end

UpdatePlayerChannelHasteMarkers = function(frame, force)
    if not (frame and frame.unit == "player") then
        return
    end

    if not (frame.MSUF_isChanneled and not frame.isEmpower) then
        HidePlayerChannelTickMarkers(frame)
        return
    end

    local enabled, tickCount, customPositions, useCustom, divisor = TickConfig(frame)
    frame._msufPlayerChannelTickRuntimeActive = enabled and true or nil
    if not enabled then
        HidePlayerChannelTickMarkers(frame)
        return
    end

    local statusBar = frame.statusBar
    if not (statusBar and statusBar.GetWidth) then
        return
    end

    EnsurePlayerChannelTickMarkers(frame, tickCount)

    local markers = frame._msufPlayerChannelHasteMarkers
    if not markers then
        return
    end

    local width = statusBar:GetWidth() or 0
    if width <= 1 then
        width = frame._msufPlayerChannelHasteMarkersLastW or 200
    end

    local lastWidth = frame._msufPlayerChannelHasteMarkersLastW
    if force or lastWidth ~= width then
        frame._msufPlayerChannelHasteMarkersLastW = width
        frame._msufPlayerChannelHasteMarkersLastF = nil

        local reverseFill = frame._msufStripeReverseFill == true
        divisor = divisor or (tickCount + 1)

        for index = 1, tickCount do
            local marker = markers[index]
            if marker and marker.SetPoint then
                if marker.SetAlpha then
                    marker:SetAlpha(1)
                end

                local offset
                if useCustom and type(customPositions) == "table" and type(customPositions[index]) == "number" then
                    local percent = customPositions[index]
                    if percent < 0 then
                        percent = 0
                    elseif percent > 100 then
                        percent = 100
                    end

                    offset = width * (percent / 100)
                else
                    local fraction = index / divisor
                    if fraction < 0.02 then
                        fraction = 0.02
                    elseif fraction > 0.98 then
                        fraction = 0.98
                    end

                    offset = width * fraction
                end

                marker:ClearAllPoints()
                if reverseFill then
                    marker:SetPoint("TOP", statusBar, "TOPRIGHT", -offset, 0)
                    marker:SetPoint("BOTTOM", statusBar, "BOTTOMRIGHT", -offset, 0)
                else
                    marker:SetPoint("TOP", statusBar, "TOPLEFT", offset, 0)
                    marker:SetPoint("BOTTOM", statusBar, "BOTTOMLEFT", offset, 0)
                end
            end
        end

        HideExtraMarkers(frame, tickCount + 1)
    end

    for index = 1, tickCount do
        local marker = markers[index]
        if marker then
            if marker.SetAlpha then
                marker:SetAlpha(1)
            end

            if marker.Show then
                marker:Show()
            end
        end
    end
end

local function UpdateCastbarChannelTicks()
    UpdatePlayerChannelHasteMarkers(_G.MSUF_PlayerCastbar, true)
    UpdatePlayerChannelHasteMarkers(_G.MSUF_PlayerCastbarPreview, true)
end
ExportPublic("MSUF_UpdateCastbarChannelTicks", UpdateCastbarChannelTicks)

ExportPublic("MSUF_IsChannelTickLinesEnabled", ChannelTickLinesEnabled)
ExportPublic("MSUF_PlayerChannelHasteMarkers_Update", UpdatePlayerChannelHasteMarkers)
ExportPublic("MSUF_PlayerChannelHasteMarkers_Hide", HidePlayerChannelTickMarkers)
ExportPublic("MSUF_PlayerChannelHasteMarkers_Ensure", EnsurePlayerChannelTickMarkers)
ExportPublic("MSUF_ApplyPlayerChannelTickMarkers", UpdateCastbarChannelTicks)
