local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
-- Player channel tick marker support.
-- Adds optional spell-aware channel markers to the player castbar using existing DB fields.
-- This augments castbar visuals only; cast/channel state remains in the shared runtime.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic
-- WoW Forever and Classic Era run Classic Era spell data: one spell ID per rank
-- and Era tick counts. TBC and Mists keep the Retail table below until their
-- spell data has been verified.
local HAS_ERA_SPELL_DATA = MSUF.Client ~= nil
    and (MSUF.Client.IsForever == true or MSUF.Client.IsVanilla == true)

local DEFAULT_MARKER_COUNT = 5
local MAX_CUSTOM_MARKER_COUNT = 10
-- Hellfire, the longest Classic Era channel below, ticks 15 times.
local MAX_AUTO_TICK_COUNT = HAS_ERA_SPELL_DATA and 15 or 12

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

-- Classic Era spell data has one spell ID per rank. Only five IDs above exist
-- there, and all five tick differently (Mind Flay 3 times, Health Funnel 10),
-- so WoW Forever and Classic Era use their own table keyed by every rank. Counts
-- are SpellDuration / EffectAuraPeriod of the channel's periodic effect in the
-- client DB of WoW Forever build 1.60.1.69876, identical to Era where the ID
-- exists; an ID that only one of the two clients knows is never the active
-- spell on the other. Evocation (a regeneration buff) and Tame Beast (a single
-- pulse) keep the default layout.
if HAS_ERA_SPELL_DATA then
    CHANNEL_TICK_DATA = {}
    local ERA_CHANNEL_TICKS = {
        [3] = {
            5143,                                        -- Arcane Missiles (rank 1)
            15407, 17311, 17312, 17313, 17314, 18807,    -- Mind Flay
            401417, 412510,                              -- Regeneration, Mass Regeneration
        },
        [4] = {
            5144,                                        -- Arcane Missiles (rank 2)
            5740, 6219, 11677, 11678,                    -- Rain of Fire
        },
        [5] = {
            5145, 8416, 8417, 10211, 10212, 25345,       -- Arcane Missiles (ranks 3-8)
            689, 699, 709, 7651, 11699, 11700,           -- Drain Life
            5138, 6226, 11703, 11704,                    -- Drain Mana
            1120, 8288, 8289, 11675,                     -- Drain Soul
            136, 3111, 3661, 3662, 13542, 13543, 13544,  -- Mend Pet
            740, 8918, 9862, 9863,                       -- Tranquility
            1260270,                                     -- Rapid Regeneration
        },
        [6] = {
            10797, 19296, 19299, 19302, 19303, 19304, 19305, -- Starshards
            1510, 14294, 14295,                          -- Volley
            413259,                                      -- Mind Sear
            1316697,                                     -- Wrack
        },
        [8] = {
            10, 6141, 8427, 10185, 10186, 10187,         -- Blizzard
        },
        [10] = {
            755, 3698, 3699, 3700, 11693, 11694, 11695,  -- Health Funnel
            16914, 17401, 17402,                         -- Hurricane
        },
        [15] = {
            1949, 11683, 11684,                          -- Hellfire
        },
    }
    for ticks, spellIDs in pairs(ERA_CHANNEL_TICKS) do
        local tickData = { ticks = ticks }
        for index = 1, #spellIDs do
            CHANNEL_TICK_DATA[spellIDs[index]] = tickData
        end
    end
end

local issecretvalue = _G.issecretvalue
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
            local marker = PixelLayoutRegion(statusBar:CreateTexture(nil, "OVERLAY", nil, 7))
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
