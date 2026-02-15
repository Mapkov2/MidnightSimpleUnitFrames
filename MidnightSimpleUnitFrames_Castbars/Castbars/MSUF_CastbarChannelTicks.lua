-- Castbars/MSUF_CastbarChannelTicks.lua
-- Phase 3 extraction: Channel haste markers (5 white static lines on player channel bar).
-- Self-contained. Only dependency: MSUF_DB (global).

-- Player-only: Channeled Cast "Haste Markers" (5 white static lines)
-- Goal: Always visible from channel START (not progress-based), positions shift with current player spell haste.
-- Secret-safe: uses only UnitSpellHaste("player") + StatusBar width. No duration math, no combat log, no secret comparisons.
-------------------------------------------------------------------------------

-- Master toggle (Options Castbars Behavior "Show channeled cast tick lines")
-- Default ON (nil treated as true). Stored in MSUF_DB.general.castbarShowChannelTicks.
local function MSUF_IsChannelTickLinesEnabled()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    if g and g.castbarShowChannelTicks == false then
        return false
    end
    return true
end

local function MSUF_PlayerChannelHasteMarkers_Ensure(self)
    if not (self and self.unit == "player") then return end
    local sb = self.statusBar
    if not (sb and sb.CreateTexture) then return end

    if self._msufPlayerChannelHasteMarkers then return end

    local stripes = {}
    for i = 1, 5 do
        local t = sb:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(1, 1, 1, 1)
        if t.SetAlpha then t:SetAlpha(1) end
        t:SetWidth(2)
        t:SetPoint("TOP", sb, "TOP", 0, 0)
        t:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
        t:Hide()
        stripes[i] = t
    end
    self._msufPlayerChannelHasteMarkers = stripes

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
    if not MSUF_IsChannelTickLinesEnabled() then
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

    MSUF_PlayerChannelHasteMarkers_Ensure(self)
    local stripes = self._msufPlayerChannelHasteMarkers
    if not stripes then return end

    local w = sb:GetWidth() or 0
    if w <= 1 then
        -- On the very first frame after show, widths can be 0; still show the markers immediately
        -- and force a proper reposition on the next size tick.
        w = self._msufPlayerChannelHasteMarkersLastW or 200
        self._msufPlayerChannelHasteMarkersForce = true
    end

    local haste = 0
    if type(UnitSpellHaste) == "function" then
        local ok, v = MSUF_FastCall(UnitSpellHaste, "player")
        if ok and type(v) == "number" then haste = v end
    end
    local factor = 1 + (haste / 100)
    if factor <= 0 then factor = 1 end

    if self._msufPlayerChannelHasteMarkersForce then
        force = true
        self._msufPlayerChannelHasteMarkersForce = nil
    end

    local lastW = self._msufPlayerChannelHasteMarkersLastW
    local lastF = self._msufPlayerChannelHasteMarkersLastF
    if not force and lastW == w and lastF == factor then
        -- no change, keep
    else
        self._msufPlayerChannelHasteMarkersLastW = w
        self._msufPlayerChannelHasteMarkersLastF = factor

        local rf = (self._msufStripeReverseFill == true)
        local anchor = rf and "RIGHT" or "LEFT"

        -- Default: 5 markers at 1/6..5/6. With haste, markers compress toward the start.
        local div = 6
        for i = 1, 5 do
            local t = stripes[i]
            if t and t.SetPoint then
                if t.SetAlpha then t:SetAlpha(1) end
                local pos = (i / div) / factor
                if pos < 0.02 then pos = 0.02 end
                if pos > 0.98 then pos = 0.98 end
                local x = w * pos
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
    end

    -- Always visible during the entire channel.
    for i = 1, #stripes do
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
        if MSUF_IsChannelTickLinesEnabled() then
            MSUF_PlayerChannelHasteMarkers_Update(frame, true)
        else
            MSUF_PlayerChannelHasteMarkers_Hide(frame)
        end
    end

    -- Real + preview (Edit Mode)
    Apply(_G.MSUF_PlayerCastbar)
    Apply(_G.MSUF_PlayerCastbarPreview)
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
