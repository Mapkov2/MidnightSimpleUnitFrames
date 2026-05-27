-- Castbars/MSUF_CastbarChannelTicks.lua
-- Phase 3 extraction: Channel tick markers (5 white static lines on player channel bar).
-- Self-contained. Only dependency: MSUF_DB (global).

-- Player-only: Channeled Cast Tick Markers.
-- Goal: Always visible from channel START (not progress-based), with static positions.
-- Secret-safe: uses only StatusBar width + static fractions. No haste reads, no duration math, no combat log, no secret comparisons.
-------------------------------------------------------------------------------

local DEFAULT_TICK_COUNT = 5
local MAX_TICKS = 10

-- Master toggle (Options Castbars Behavior "Show channeled cast tick lines").
-- Custom player tick settings are preserved for older profiles/imports.
local function MSUF_GetPlayerChannelTickConfig()
    local db = MSUF_DB
    local g = db and db.general or nil
    local pc = db and db.player and db.player.castbar or nil
    local custom = pc and pc.channelTickUseCustom == true

    if not custom and not (g and g.castbarShowChannelTicks == true) then
        return false, 0, nil, false
    end

    local count = custom and tonumber(pc.channelTickCount) or DEFAULT_TICK_COUNT
    count = count or DEFAULT_TICK_COUNT
    if count < 0 then
        count = 0
    elseif count > MAX_TICKS then
        count = MAX_TICKS
    end

    return count > 0, count, custom and pc.channelTickPosPct or nil, custom
end

local function MSUF_IsChannelTickLinesEnabled()
    local enabled = MSUF_GetPlayerChannelTickConfig()
    return enabled == true
end

local function MSUF_PlayerChannelHasteMarkers_Ensure(self, count)
    if not (self and self.unit == "player") then return end
    local sb = self.statusBar
    if not (sb and sb.CreateTexture) then return end

    local stripes = self._msufPlayerChannelHasteMarkers
    if not stripes then
        stripes = {}
        self._msufPlayerChannelHasteMarkers = stripes
    end

    count = count or DEFAULT_TICK_COUNT
    for i = 1, count do
        if stripes[i] then
            -- already created
        else
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
            if self then
                self._msufPlayerChannelHasteMarkersForce = true
            end
        end)
    end
end

local function MSUF_PlayerChannelHasteMarkers_HideFrom(self, index)
    local stripes = self and self._msufPlayerChannelHasteMarkers
    if not stripes then return end
    for i = index, #stripes do
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
    end
end

local function MSUF_PlayerChannelHasteMarkers_Update(self, force)
    if not (self and self.unit == "player") then return end

    -- Respect the menu toggle; if disabled, force-hide markers immediately.
    local enabled, count, customPositions, custom = MSUF_GetPlayerChannelTickConfig()
    if not enabled then
        MSUF_PlayerChannelHasteMarkers_Hide(self)
        return
    end

    -- Only for channels; never for empower.
    if not (self.MSUF_isChanneled and not self.isEmpower) then
        MSUF_PlayerChannelHasteMarkers_Hide(self)
        return
    end

    local sb = self.statusBar
    if not (sb and sb.GetWidth) then return end

    MSUF_PlayerChannelHasteMarkers_Ensure(self, count)
    local stripes = self._msufPlayerChannelHasteMarkers
    if not stripes then return end

    local w = sb:GetWidth() or 0
    if w <= 1 then
        -- On the very first frame after show, widths can be 0; still show the markers immediately
        -- and force a proper reposition on the next size tick.
        w = self._msufPlayerChannelHasteMarkersLastW or 200
        self._msufPlayerChannelHasteMarkersForce = true
    end

    if self._msufPlayerChannelHasteMarkersForce then
        force = true
        self._msufPlayerChannelHasteMarkersForce = nil
    end

    local lastW = self._msufPlayerChannelHasteMarkersLastW
    if not force and lastW == w then
        -- no change, keep
    else
        self._msufPlayerChannelHasteMarkersLastW = w
        self._msufPlayerChannelHasteMarkersLastF = nil

        local rf = (self._msufStripeReverseFill == true)

        -- Static markers. Decorative only; never depends on haste.
        local div = count + 1
        for i = 1, count do
            local t = stripes[i]
            if t and t.SetPoint then
                if t.SetAlpha then t:SetAlpha(1) end
                local x
                if custom and type(customPositions) == "table" and type(customPositions[i]) == "number" then
                    local pct = customPositions[i]
                    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
                    x = w * (pct / 100)
                else
                    local pos = i / div
                    if pos < 0.02 then pos = 0.02 end
                    if pos > 0.98 then pos = 0.98 end
                    x = w * pos
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
        MSUF_PlayerChannelHasteMarkers_HideFrom(self, count + 1)
    end

    -- Always visible during the entire channel.
    for i = 1, count do
        local t = stripes[i]
        if t then
            if t.SetAlpha then t:SetAlpha(1) end
            if t.Show then t:Show() end
        end
    end
end


-- Export: Options can call this to apply immediately (overrides core LoD stub).
function _G.MSUF_UpdateCastbarChannelTicks()
    -- Real + preview (Edit Mode)
    MSUF_PlayerChannelHasteMarkers_Update(_G.MSUF_PlayerCastbar, true)
    MSUF_PlayerChannelHasteMarkers_Update(_G.MSUF_PlayerCastbarPreview, true)
end



-- Vehicle support: while in a vehicle, some casts/channels are reported on unit "vehicle" instead of "player".
-- Keep frame.unit as "player" for options/anchoring, but query the effective unit for cast APIs.

---------------------------------------------------------------------------
-- _G exports
---------------------------------------------------------------------------
_G.MSUF_IsChannelTickLinesEnabled          = MSUF_IsChannelTickLinesEnabled
_G.MSUF_PlayerChannelHasteMarkers_Update   = MSUF_PlayerChannelHasteMarkers_Update
_G.MSUF_PlayerChannelHasteMarkers_Hide     = MSUF_PlayerChannelHasteMarkers_Hide
_G.MSUF_PlayerChannelHasteMarkers_Ensure   = MSUF_PlayerChannelHasteMarkers_Ensure
_G.MSUF_ApplyPlayerChannelTickMarkers      = _G.MSUF_UpdateCastbarChannelTicks
