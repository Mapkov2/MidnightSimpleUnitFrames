-- Player channel tick marker support.
-- Adds optional haste/channel tick markers to the player castbar using existing DB fields.
-- This augments castbar visuals only; cast/channel state remains in the shared runtime.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local DEFAULT_TICK_COUNT = 5
local MAX_TICK_COUNT = 10

local function TickConfig()
    local db = MSUF_DB
    local general = db and db.general or nil
    local playerCastbar = db and db.player and db.player.castbar or nil

    local useCustom = playerCastbar and playerCastbar.channelTickUseCustom == true
    if not useCustom and not (general and general.castbarShowChannelTicks == true) then
        return false, 0, nil, false
    end

    local tickCount = useCustom and tonumber(playerCastbar.channelTickCount) or DEFAULT_TICK_COUNT
    tickCount = tickCount or DEFAULT_TICK_COUNT

    if tickCount < 0 then
        tickCount = 0
    elseif tickCount > MAX_TICK_COUNT then
        tickCount = MAX_TICK_COUNT
    end

    return tickCount > 0, tickCount, useCustom and playerCastbar.channelTickPosPct or nil, useCustom
end

local function ChannelTickLinesEnabled()
    local enabled = TickConfig()
    return enabled == true
end

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

    tickCount = tickCount or DEFAULT_TICK_COUNT
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
            if frame then
                frame._msufPlayerChannelHasteMarkersForce = true
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
    end
end

local function UpdatePlayerChannelHasteMarkers(frame, force)
    if not (frame and frame.unit == "player") then
        return
    end

    local enabled, tickCount, customPositions, useCustom = TickConfig()
    if not enabled then
        HidePlayerChannelTickMarkers(frame)
        return
    end

    if not (frame.MSUF_isChanneled and not frame.isEmpower) then
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
        frame._msufPlayerChannelHasteMarkersForce = true
    end

    if frame._msufPlayerChannelHasteMarkersForce then
        force = true
        frame._msufPlayerChannelHasteMarkersForce = nil
    end

    local lastWidth = frame._msufPlayerChannelHasteMarkersLastW
    if force or lastWidth ~= width then
        frame._msufPlayerChannelHasteMarkersLastW = width
        frame._msufPlayerChannelHasteMarkersLastF = nil

        local reverseFill = frame._msufStripeReverseFill == true
        local divisor = tickCount + 1

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
