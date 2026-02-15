-- Castbars/MSUF_PlayerCastbarRuntime.lua
--  extraction: Player castbar runtime (latency, color, interrupt, cast, OnEvent).
-- Loaded AFTER Empower + ChannelTicks (needs _G exports from those files).

local MSUF_FastCall = _G.MSUF_FastCall or function(...) return pcall(...) end
local _EnsureDBLazy = _G.MSUF_EnsureDBLazy or function()
    if not MSUF_DB and type(EnsureDB) == "function" then EnsureDB() end
end

-- Cross-file refs (call-time resolved, set by earlier TOC files)
local MSUF_PlayerCastbar_EmpowerStart       = function(s, id) local fn = _G.MSUF_PlayerCastbar_EmpowerStart; if fn then fn(s, id) end end
local MSUF_PlayerCastbar_ClearEmpower       = function(s, h) local fn = _G.MSUF_PlayerCastbar_ClearEmpower; if fn then fn(s, h) end end
local MSUF_PlayerChannelHasteMarkers_Update = function(s, f) local fn = _G.MSUF_PlayerChannelHasteMarkers_Update; if fn then fn(s, f) end end
local MSUF_PlayerChannelHasteMarkers_Hide   = function(s) local fn = _G.MSUF_PlayerChannelHasteMarkers_Hide; if fn then fn(s) end end

local function MSUF_PlayerCastbar_UpdateLatencyZone(self, isChanneled, durSec)
    if not self or not self.latencyBar or not self.statusBar then
        return
    end

    -- Honor Options -> Castbars -> Style -> Show latency indicator (default ON)
    _EnsureDBLazy()  -- P3 Fix #14: lazy guard
    local g = (MSUF_DB and MSUF_DB.general) or {}
    if g.castbarShowLatency == false then
        self.latencyBar:Hide()
        return
    end

    -- For Edit Mode previews / dummy casts: show the indicator only while MSUF Edit Mode is active.
    if (self.MSUF_testMode or self._msufIsPreview) and not MSUF_UnitEditModeActive then
        self.latencyBar:Hide()
        return
    end

    if not durSec or type(durSec) ~= "number" or durSec <= 0 then
        self.latencyBar:Hide()
        return
    end

    local _, _, homeMS, worldMS = GetNetStats()
    local latencyMS = math.max(homeMS or 0, worldMS or 0)
    local queueMS = tonumber(GetCVar("SpellQueueWindow") or "0") or 0
    local tolMS = math.max(latencyMS, queueMS)

    local durationMS = durSec * 1000
    local pct = 0
    if durationMS > 0 then
        pct = tolMS / durationMS
    end
    if pct > 1 then pct = 1 end
    if pct < 0 then pct = 0 end

    self.MSUF_latencyLastPct = pct
    self.MSUF_latencyLastIsChanneled = isChanneled and true or false
    self.MSUF_latencyLastDurSec = durSec

    local barW = self.statusBar:GetWidth() or 0
    local w = barW * pct

    if (not barW or barW <= 1) and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not self or not self.latencyBar or not self.statusBar then return end
            local bw = self.statusBar:GetWidth() or 0
            local ww = bw * (self.MSUF_latencyLastPct or 0)
            local isChan = self.MSUF_latencyLastIsChanneled and true or false
            local reverse = _G.MSUF_GetReverseFillSafe(self, isChan)
            local anchorOnLeft = reverse and true or false  -- finish edge (value always increases)

            self.latencyBar:ClearAllPoints()
            if anchorOnLeft then
                self.latencyBar:SetPoint("TOPLEFT", self.statusBar, "TOPLEFT", 0, 0)
                self.latencyBar:SetPoint("BOTTOMLEFT", self.statusBar, "BOTTOMLEFT", 0, 0)
            else
                self.latencyBar:SetPoint("TOPRIGHT", self.statusBar, "TOPRIGHT", 0, 0)
                self.latencyBar:SetPoint("BOTTOMRIGHT", self.statusBar, "BOTTOMRIGHT", 0, 0)
            end
            self.latencyBar:SetWidth(ww)
            if ww and ww > 0 then
                self.latencyBar:Show()
            else
                self.latencyBar:Hide()
            end
        end)
        return
    end

    local reverse = _G.MSUF_GetReverseFillSafe(self, isChanneled)
    local anchorOnLeft = reverse and true or false  -- finish edge (value always increases)

    self.latencyBar:ClearAllPoints()
    if anchorOnLeft then
        self.latencyBar:SetPoint("TOPLEFT", self.statusBar, "TOPLEFT", 0, 0)
        self.latencyBar:SetPoint("BOTTOMLEFT", self.statusBar, "BOTTOMLEFT", 0, 0)
    else
        self.latencyBar:SetPoint("TOPRIGHT", self.statusBar, "TOPRIGHT", 0, 0)
        self.latencyBar:SetPoint("BOTTOMRIGHT", self.statusBar, "BOTTOMRIGHT", 0, 0)
    end
    self.latencyBar:SetWidth(w)
    if w and w > 0 then
        self.latencyBar:Show()
    else
        self.latencyBar:Hide()
    end
end

local function MSUF_PlayerCastbar_UpdateColorForInterruptible(self)
    if not self or not self.statusBar then
        return
    end

    _EnsureDBLazy()  -- P3 Fix #14: lazy guard
    local g = MSUF_DB and MSUF_DB.general or {}

    -- Optional player castbar color override (normal casts/channels).
    -- This overrides interruptible + non-interruptible colors for the player castbar.
    -- Interrupt feedback ("Interrupted") still uses the interrupt feedback color.
    if g.playerCastbarOverrideEnabled then
        -- If interrupt feedback is active, keep the interrupt feedback color.
        if not (self.interruptFeedbackEndTime and GetTime() < self.interruptFeedbackEndTime) then
            local mode = g.playerCastbarOverrideMode
            local orr, org, orb
            if mode == "CUSTOM" then
                orr = tonumber(g.playerCastbarOverrideR)
                org = tonumber(g.playerCastbarOverrideG)
                orb = tonumber(g.playerCastbarOverrideB)
            else
                local _, classToken = UnitClass("player")
                if classToken then
                    if type(MSUF_GetClassBarColor) == "function" then
                        orr, org, orb = MSUF_GetClassBarColor(classToken)
                    end
                    if (not orr) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                        local c = RAID_CLASS_COLORS[classToken]
                        orr, org, orb = c.r, c.g, c.b
                    end
                end
            end

            if orr and org and orb then
                if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
                    _G.MSUF_SetStatusBarColorIfChanged(self.statusBar, orr, org, orb, 1)
                else
                    self.statusBar:SetStatusBarColor(orr, org, orb, 1)
                end
                return
            end
        end
    end

    local nonInterruptibleKey = g.castbarNonInterruptibleColor or "red"

    local isNonInterruptible = false

    local unit = self.unit or "player"
    local nameplate = C_NamePlate
        and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit(unit, issecure())

    if nameplate then
        local bar = (nameplate.UnitFrame and nameplate.UnitFrame.castBar)
            or nameplate.castBar
            or nameplate.CastBar

        local barType = bar and bar.barType
        if barType == "uninterruptable"
            or barType == "uninterruptible"
            or barType == "uninterruptibleSpell"
            or barType == "shield"
        then
            isNonInterruptible = true
        end
    end

    if self.isNotInterruptible then
        isNonInterruptible = true
    end

    local r, gCol, b, a

    if isNonInterruptible then
        if MSUF_GetNonInterruptibleCastColor then
            r, gCol, b = MSUF_GetNonInterruptibleCastColor()
            a = 1
        end

        if not r or not gCol or not b then
            local nonKey = g.castbarNonInterruptibleColor or "red"
            if MSUF_GetColorFromKey then
                local color = MSUF_GetColorFromKey(nonKey)
                if color then
                    r, gCol, b, a = color:GetRGBA()
                end
            end
        end

        if not r or not gCol or not b then
            r, gCol, b, a = 0.4, 0.01, 0.01, 1
        end
    else
        if MSUF_GetInterruptibleCastColor then
            r, gCol, b = MSUF_GetInterruptibleCastColor()
            a = 1
        end

        if not r or not gCol or not b then
            local interruptibleKey = g.castbarInterruptibleColor or "turquoise"
            if MSUF_GetColorFromKey then
                local color = MSUF_GetColorFromKey(interruptibleKey)
                if color then
                    r, gCol, b, a = color:GetRGBA()
                end
            end
        end

        if not r or not gCol or not b then
            r, gCol, b, a = 0, 1, 0.9, 1
        end
    end

    if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
        _G.MSUF_SetStatusBarColorIfChanged(self.statusBar, r, gCol, b, a or 1)
    else
        self.statusBar:SetStatusBarColor(r, gCol, b, a or 1)
    end
end
local function MSUF_GetInterruptFeedbackColor()
    _EnsureDBLazy()  -- P3 Fix #14: lazy guard
    local g = MSUF_DB and MSUF_DB.general or {}

    local r    = tonumber(g.castbarInterruptR)
    local gCol = tonumber(g.castbarInterruptG)
    local b    = tonumber(g.castbarInterruptB)

    if r and gCol and b then
        return r, gCol, b, 1
    end

    local key = g.castbarInterruptColor or "red"

    if MSUF_GetColorFromKey then
        local color = MSUF_GetColorFromKey(key)
        if color then
            return color:GetRGBA()
        end
    end

    return 0.8, 0.1, 0.1, 1
end
local MSUF_PLAYER_INTERRUPT_FEEDBACK_DURATION = (_G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5)

local function MSUF_PlayerCastbar_HideIfNoLongerCasting(timer)
    local self = timer and timer.msuCastbarFrame
    if not self or not self.unit then
        return
    end

    if self.MSUF_testMode then
        return
    end

    local castName = UnitCastingInfo(self.unit)
    local chanName = UnitChannelInfo(self.unit)

    if castName or chanName then
        if MSUF_PlayerCastbar_Cast then
            MSUF_PlayerCastbar_Cast(self)
        end
        return
    end

    self:SetScript("OnUpdate", nil)
    if self.timeText then
        MSUF_SetTextIfChanged(self.timeText, "")
    end
    if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(self) end
    self:Hide()
end

local function MSUF_PlayerCastbar_ShowInterruptFeedback(self, label)
    if not self or not self.statusBar then
        return
    end

    _EnsureDBLazy()  -- P3 Fix #14: lazy guard
    local p = (MSUF_DB and MSUF_DB.player) or {}
    if p.showInterrupt == false then
        -- Option disabled: no red 'Interrupted' feedback, just hide immediately.
        self:SetScript("OnUpdate", nil)
        self.interruptFeedbackEndTime = nil
        if self.timeText then MSUF_SetTextIfChanged(self.timeText, "") end
        if self.statusBar and self.statusBar.SetValue then MSUF_FastCall(self.statusBar.SetValue, self.statusBar, 0) end
        self:Hide()
        return
    end

    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end

    self:SetScript("OnUpdate", nil)

    if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(self) end
    self.MSUF_durationObj = nil
    self.MSUF_channelDirect = nil
    self.MSUF_timerDriven = nil
    self.MSUF_timerRangeSet = nil
    if _G.MSUF_ClearCastbarTimerDuration and self.statusBar then
        _G.MSUF_ClearCastbarTimerDuration(self.statusBar)
    end

    self._msufActiveCastUnit = nil
    self._msufChanNilSince = nil
    self.interruptFeedbackEndTime = GetTime() + MSUF_PLAYER_INTERRUPT_FEEDBACK_DURATION

    -- Phase 2A: Use shared interrupt bar visuals (replaces ~25 lines of inline setup).
    local rf = _G.MSUF_GetReverseFillSafe and _G.MSUF_GetReverseFillSafe(self, false) or false
    _G.MSUF_ApplyInterruptBarVisuals(self, {
        barValue = 0.8,
        colorR = 0.8, colorG = 0.1, colorB = 0.1,
        reverseFill = rf,
        label = label or INTERRUPTED,
    })

    local grace = MSUF_PLAYER_INTERRUPT_FEEDBACK_DURATION
    if type(grace) ~= 'number' then grace = 0.5 end
    if grace < 0 then grace = 0 end

    self.hideTimer = C_Timer.NewTimer(grace, MSUF_PlayerCastbar_HideIfNoLongerCasting)
    self.hideTimer.msuCastbarFrame = self
end

local function MSUF_PlayerCastbar_GetEffectiveUnit(self)
    local u = (self and self.unit) or "player"
    if u == "player" and type(UnitHasVehicleUI) == "function" and UnitHasVehicleUI("player") then
        if type(UnitExists) == "function" and UnitExists("vehicle") then
            -- Prefer vehicle only if it actually has an active cast/channel.
            if (type(UnitCastingInfo) == "function" and UnitCastingInfo("vehicle"))
            or (type(UnitChannelInfo) == "function" and UnitChannelInfo("vehicle")) then
                return "vehicle"
            end
        end
    end
    return u
end



-- Quick Win #1: Lookup tables hoisted to file-level upvalues (previously allocated per-call inside the function).
local _MSUF_UNHALTED_CAST_START = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_INTERRUPTIBLE = true,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
    UNIT_SPELLCAST_SENT = true,
}
local _MSUF_UNHALTED_CAST_STOP = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
}
local _MSUF_UNHALTED_CHANNEL_START = {
    UNIT_SPELLCAST_CHANNEL_START = true,
}

-- Unhalted-style non-empower player castbar (cast/channel): self-driven via OnUpdate and hard-stops when the cast/channel is gone.
local function MSUF_PlayerCastbar_UnhaltedUpdate(self, event)
    if not self or not self.unit or not self.statusBar then return end
    if self.isEmpower then return end

    local CAST_START = _MSUF_UNHALTED_CAST_START
    local CAST_STOP = _MSUF_UNHALTED_CAST_STOP
    local CHANNEL_START = _MSUF_UNHALTED_CHANNEL_START

    local unit = MSUF_PlayerCastbar_GetEffectiveUnit(self)

    if CAST_START[event] then
        local castDuration = (type(UnitCastingDuration) == "function") and UnitCastingDuration(unit) or nil
        if not castDuration then return end

        -- Clear any short interrupt-feedback window when a new cast starts (cancel -> re-cast)
        -- and track the unit the cast is coming from (player vs vehicle).
        self.interruptFeedbackEndTime = nil
        self._msufActiveCastUnit = unit

        self.MSUF_castDuration = castDuration
        self.MSUF_channelDuration = nil

        -- Phase 1C + 1B: Use shared reverseFill + timer direction helpers.
        local __msuf_rf = _G.MSUF_GetReverseFillSafe(self, false)
        _G.MSUF_ApplyTimerAndFill(self.statusBar, castDuration, __msuf_rf)


        -- Ensure fill direction updates for this cast type (cast vs channel) immediately.
        self.MSUF_isChanneled = false
        MSUF_PlayerChannelHasteMarkers_Hide(self)
	    local castName, castText, castTex, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
	    -- IMPORTANT (Midnight/Beta): do NOT apply boolean operators (e.g. `not not x`) to potentially-secret values.
	    -- Derive a plain Lua boolean via a truthiness branch.
	    local apiNI = false
	    if notInterruptible then apiNI = true end
	    self.isNotInterruptible = apiNI
        if self.icon then self.icon:SetTexture(castTex or nil) end
        if self.castText then MSUF_SetTextIfChanged(self.castText, castName or "") end

        -- Apply current (possibly overridden) player castbar color.
        MSUF_PlayerCastbar_UpdateColorForInterruptible(self)

        -- Latency indicator (only real castbar, not previews).
        do
            local durSec = nil
            if castDuration and castDuration.GetTotalDuration then
                local okT, total = MSUF_FastCall(castDuration.GetTotalDuration, castDuration)
                if okT then durSec = total end
            end
            if durSec == nil and castDuration and castDuration.GetRemainingDuration then
                local okR, rem = MSUF_FastCall(castDuration.GetRemainingDuration, castDuration)
                if okR then durSec = rem end
            end
            MSUF_PlayerCastbar_UpdateLatencyZone(self, false, durSec)
        end

        self:SetScript("OnUpdate", nil)
        self._msufCastNilSince = nil
        self.MSUF_durationObj = castDuration
        self.MSUF_timerDriven = true
        -- Duration Objects + SetTimerDuration animate the fill; the manager only ticks for time text / glow fade / hard-stop safety.
        MSUF_EnsureCastbarManager()
        if MSUF_RegisterCastbar then
            MSUF_RegisterCastbar(self)
        end
        if _G.MSUF_UpdateCastbarFrame then
            local _now = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
            _G.MSUF_UpdateCastbarFrame(self, 0, _now)
        end

        self:Show()
        return
    end

    if CHANNEL_START[event] then
        local channelDuration = (type(UnitChannelDuration) == "function") and UnitChannelDuration(unit) or nil
        if not channelDuration then return end

        -- Clear any short interrupt-feedback window when a new channel starts and track unit source.
        self.interruptFeedbackEndTime = nil
        self._msufActiveCastUnit = unit
        self._msufChanNilSince = nil

        self.MSUF_channelDuration = channelDuration
        self.MSUF_castDuration = nil

        -- Phase 1C + 1B: Use shared reverseFill + timer direction helpers.
        local __msuf_rf = _G.MSUF_GetReverseFillSafe(self, true)
        _G.MSUF_ApplyTimerAndFill(self.statusBar, channelDuration, __msuf_rf)


        -- Ensure fill direction updates for this cast type (cast vs channel) immediately.
        self.MSUF_isChanneled = true
        self._msufStripeReverseFill = (__msuf_rf and true or false)
        MSUF_PlayerChannelHasteMarkers_Update(self, true)
	        local chanName, chanText, chanTex, _, _, _, notInterruptible = UnitChannelInfo(unit)
	        -- IMPORTANT (Midnight/Beta): do NOT apply boolean operators (e.g. `not not x`) to potentially-secret values.
	        -- Derive a plain Lua boolean via a truthiness branch.
	        local apiNI = false
	        if notInterruptible then apiNI = true end
	        self.isNotInterruptible = apiNI
        if self.icon then self.icon:SetTexture(chanTex or nil) end
        if self.castText then MSUF_SetTextIfChanged(self.castText, chanName or "") end

        -- Apply current (possibly overridden) player castbar color.
        MSUF_PlayerCastbar_UpdateColorForInterruptible(self)

        -- Cache total duration for latency indicator etc., but do NOT touch MinMax while timer-driven.
        -- Setting SetMinMaxValues after SetTimerDuration can stop the internal timer animation (seen on "permanent" channels like Mind Flay).
        do
            local total = nil
            if channelDuration and channelDuration.GetTotalDuration then
                local okTotal, t = MSUF_FastCall(channelDuration.GetTotalDuration, channelDuration)
                if okTotal then total = t end
            end
            self.MSUF_channelTotal = total
        end

        -- Latency indicator (only real castbar, not previews).
        do
            local durSec = self.MSUF_channelTotal
            if durSec == nil and channelDuration and channelDuration.GetTotalDuration then
                local okT, total = MSUF_FastCall(channelDuration.GetTotalDuration, channelDuration)
                if okT then durSec = total end
            end
            if durSec == nil and channelDuration and channelDuration.GetRemainingDuration then
                local okR, rem = MSUF_FastCall(channelDuration.GetRemainingDuration, channelDuration)
                if okR then durSec = rem end
            end
            MSUF_PlayerCastbar_UpdateLatencyZone(self, true, durSec)
        end

        self:SetScript("OnUpdate", nil)
        self._msufChanNilSince = nil
        self.MSUF_durationObj = channelDuration
        self.MSUF_timerDriven = true
        -- Duration Objects + SetTimerDuration animate the fill; the manager only ticks for time text / glow fade / hard-stop safety.
        MSUF_EnsureCastbarManager()
        if MSUF_RegisterCastbar then
            MSUF_RegisterCastbar(self)
        end
        if _G.MSUF_UpdateCastbarFrame then
            local _now = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
            _G.MSUF_UpdateCastbarFrame(self, 0, _now)
        end

        self:Show()
        return
    end

    if CAST_STOP[event] then
        self:SetScript("OnUpdate", nil)
        self._msufChanNilSince = nil
        self._msufCastNilSince = nil
        self._msufHardStopNilSince = nil
        self.MSUF_durationObj = nil
        self.MSUF_timerDriven = nil
        if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(self) end

        MSUF_PlayerChannelHasteMarkers_Hide(self)
        if self.latencyBar then self.latencyBar:Hide() end
        if self.timeText then MSUF_SetTextIfChanged(self.timeText, "") end
        if self.statusBar and self.statusBar.SetValue then MSUF_FastCall(self.statusBar.SetValue, self.statusBar, 0) end
        self:Hide()
        return
    end
end


local function MSUF_PlayerCastbar_Cast(self)
    if not self or not self.unit or not self.statusBar then return end
    if self.isEmpower then return end
    if self.MSUF_testMode then return end

    -- Re-evaluate live state and apply Unhalted-style updates.
    if UnitCastingInfo(self.unit) then
        MSUF_PlayerCastbar_UnhaltedUpdate(self, "UNIT_SPELLCAST_START")
    elseif UnitChannelInfo(self.unit) then
        MSUF_PlayerCastbar_UnhaltedUpdate(self, "UNIT_SPELLCAST_CHANNEL_START")
    else
        MSUF_PlayerCastbar_UnhaltedUpdate(self, "UNIT_SPELLCAST_STOP")
    end
end

function _G.MSUF_UpdateCastbarLatencyIndicator()
    local f = _G.MSUF_PlayerCastBar or _G.MSUF_PlayerCastbar
    if not f or not f.latencyBar or not f.statusBar then return end

    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    if g.castbarShowLatency == false then
        f.latencyBar:Hide()
        return
    end

    if (f.MSUF_testMode or f._msufIsPreview) and not MSUF_UnitEditModeActive then
        f.latencyBar:Hide()
        return
    end

    local unit = f.unit or "player"
    if UnitChannelInfo(unit) then
        local durSec = f.MSUF_channelTotal
        local obj = f.MSUF_channelDuration
        if durSec == nil and obj and obj.GetTotalDuration then
            local okT, total = MSUF_FastCall(obj.GetTotalDuration, obj)
            if okT then durSec = total end
        end
        if durSec == nil and obj and obj.GetRemainingDuration then
            local okR, rem = MSUF_FastCall(obj.GetRemainingDuration, obj)
            if okR then durSec = rem end
        end
        MSUF_PlayerCastbar_UpdateLatencyZone(f, true, durSec)
        return
    end

    if UnitCastingInfo(unit) then
        local durSec = nil
        local obj = f.MSUF_castDuration
        if obj and obj.GetTotalDuration then
            local okT, total = MSUF_FastCall(obj.GetTotalDuration, obj)
            if okT then durSec = total end
        end
        if durSec == nil and obj and obj.GetRemainingDuration then
            local okR, rem = MSUF_FastCall(obj.GetRemainingDuration, obj)
            if okR then durSec = rem end
        end
        MSUF_PlayerCastbar_UpdateLatencyZone(f, false, durSec)
        return
    end

    f.latencyBar:Hide()
end

local function MSUF_PlayerCastbar_OnEvent(self, event, ...)
    if not MSUF_IsCastbarEnabledForUnit("player") then
        if type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
            _G.MSUF_PlayerGCDBar_Stop(self)
        end
        self:SetScript("OnUpdate", nil)
        if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(self) end
        self.interruptFeedbackEndTime = nil
        if self.timeText then
            MSUF_SetTextIfChanged(self.timeText, "")
        end
        if self.latencyBar then
            self.latencyBar:Hide()
        end
        self:Hide()
        return
    end

    if self.MSUF_testMode then
        return
    end


    -- Empowered casts: must bypass the GCD bar and MUST be handled even while empower is active.
    if event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        if type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
            _G.MSUF_PlayerGCDBar_Stop(self, true)
        end
        MSUF_PlayerCastbar_EmpowerStart(self, select(3, ...))
        return
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        MSUF_PlayerCastbar_ClearEmpower(self, true)
        return
    end

    -- While empowering, also react to generic stop/failed/succeeded/interrupt events.
    if self.isEmpower then
        if event == "UNIT_SPELLCAST_INTERRUPTED" then
            if type(_G.MSUF_PlayerCastbar_ShowInterruptFeedback) == "function" then
                _G.MSUF_PlayerCastbar_ShowInterruptFeedback(self, "Interrupted")
            else
                MSUF_PlayerCastbar_ClearEmpower(self, true)
            end
            return
        elseif event == "UNIT_SPELLCAST_STOP"
            or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_SUCCEEDED" then
            MSUF_PlayerCastbar_ClearEmpower(self, true)
            return
        end
    end


    -- Interrupted (non-empower): show short red feedback window (Blizzard-style) if enabled.
    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unitToken = ...
        -- Ignore interrupts from the non-active unit (player vs vehicle) to avoid false flashes.
        if self._msufActiveCastUnit and unitToken and unitToken ~= self._msufActiveCastUnit then
            return
        end

        if type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
            _G.MSUF_PlayerGCDBar_Stop(self, true)
        end

        MSUF_PlayerCastbar_ShowInterruptFeedback(self, INTERRUPTED)
        return
    end

    -- Unhalted-style handling for non-empower cast/channel events (player).
    if not self.isEmpower then
        if event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_SENT"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_INTERRUPTIBLE"
        or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            if type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
                _G.MSUF_PlayerGCDBar_Stop(self, true)
            end
            MSUF_PlayerCastbar_UnhaltedUpdate(self, event)
            return
        end
    end


    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        self.isNotInterruptible = false
        MSUF_PlayerCastbar_UpdateColorForInterruptible(self)
        return

    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        self.isNotInterruptible = true
        MSUF_PlayerCastbar_UpdateColorForInterruptible(self)
        return
    end
end

---------------------------------------------------------------------------
-- _G exports
---------------------------------------------------------------------------
_G.MSUF_PlayerCastbar_UpdateLatencyZone           = MSUF_PlayerCastbar_UpdateLatencyZone
_G.MSUF_PlayerCastbar_UpdateColorForInterruptible = MSUF_PlayerCastbar_UpdateColorForInterruptible
_G.MSUF_GetInterruptFeedbackColor                 = MSUF_GetInterruptFeedbackColor
_G.MSUF_PlayerCastbar_HideIfNoLongerCasting       = MSUF_PlayerCastbar_HideIfNoLongerCasting
_G.MSUF_PlayerCastbar_ShowInterruptFeedback       = MSUF_PlayerCastbar_ShowInterruptFeedback
_G.MSUF_PlayerCastbar_GetEffectiveUnit            = MSUF_PlayerCastbar_GetEffectiveUnit
_G.MSUF_PlayerCastbar_UnhaltedUpdate              = MSUF_PlayerCastbar_UnhaltedUpdate
_G.MSUF_PlayerCastbar_Cast                        = MSUF_PlayerCastbar_Cast
_G.MSUF_PlayerCastbar_OnEvent                     = MSUF_PlayerCastbar_OnEvent
-- MSUF_UpdateCastbarLatencyIndicator is already defined directly on _G
