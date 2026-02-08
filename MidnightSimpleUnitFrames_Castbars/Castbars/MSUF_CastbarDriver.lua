-- BUILD_ID: MSUF_driver_clean_replace_2026-01-08
-- Castbars/MSUF_CastbarDriver.lua
-- Step 14: Spawn + driver split.
-- Owns creation of Target/Focus castbar frames and the EventBus driver that creates them on login.
-- Keeps MSUF_Castbars.lua focused on runtime/update + reanchor/apply utilities.

-- -------------------------------------------------
-- Step 14: Driver-side cast-state change detector (max performance)
-- Avoid redundant :Cast() rebuilds when the cast state hasn't actually changed.
-- -------------------------------------------------
local addonName, ns = ...

-- Shared interrupt feedback hold duration (seconds). Keep boss/target/focus consistent.
_G.MSUF_INTERRUPT_FEEDBACK_DURATION = _G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5


-- Step 5 (engine/state): driver-side safe fallback for enabled checks.
-- MSUF_IsCastbarEnabledForUnit is normally provided by MSUF_Castbars.lua, but this file can
-- receive events very early (or in partial-load scenarios). Avoid hard nil errors.
local function MSUF_Driver_IsCastbarEnabled(unit)
    unit = unit or ""
    local fn = _G.MSUF_IsCastbarEnabledForUnit
    if type(fn) == "function" then
        local ok, res = pcall(fn, unit)
        if ok and res ~= nil then
            return res
        end
    end

    if type(_G.MSUF_EnsureDB) == "function" then
        pcall(_G.MSUF_EnsureDB)
    end

    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    if not g then
        return true
    end

    if unit == "player" then
        return g.enablePlayerCastbar ~= false
    elseif unit == "target" then
        return g.enableTargetCastbar ~= false
    elseif unit == "focus" then
        return g.enableFocusCastbar ~= false
    else
        -- Boss/pet/etc are handled in their respective modules; assume enabled to avoid breaking casts.
        return true
    end
end



-- Step 5 (perf, smoothness-safe): cache expensive UI calls.
-- Avoid repeated StatusBar:SetStatusBarColor with identical values.
function _G.MSUF_SetStatusBarColorIfChanged(sb, r, g, b, a)
    if not sb or not sb.SetStatusBarColor then return end
    if a == nil then a = 1 end

    -- Cache the "base" (non-derived) fill color for optional end-of-cast glow/fade.
    -- Callers that apply a derived color MUST set `sb._msufGlowSkipBase = true`
    -- while calling this helper, otherwise we'll overwrite the base color.
    if not sb._msufGlowSkipBase then
        local br, bg, bb, ba = sb._msufGlowBaseR, sb._msufGlowBaseG, sb._msufGlowBaseB, sb._msufGlowBaseA
        if br ~= r or bg ~= g or bb ~= b or ba ~= a then
            sb._msufGlowBaseR, sb._msufGlowBaseG, sb._msufGlowBaseB, sb._msufGlowBaseA = r, g, b, a
            -- Force the fade to recompute next tick when the base color changes.
            sb._msufGlowLastP = nil
        end
    end
    local lr, lg, lb, la = sb._msufLastColorR, sb._msufLastColorG, sb._msufLastColorB, sb._msufLastColorA
    if lr == r and lg == g and lb == b and la == a then return end
    sb._msufLastColorR, sb._msufLastColorG, sb._msufLastColorB, sb._msufLastColorA = r, g, b, a
    if type(_G.MSUF_FastCall) == "function" then
        _G.MSUF_FastCall(sb.SetStatusBarColor, sb, r, g, b, a)
    else
        sb:SetStatusBarColor(r, g, b, a)
    end
end


local function MSUF__EnsurePlayerChannelHasteStripes(frame)
    if not (frame and frame.unit == "player") then return end

    local sb = frame.statusBar
    if not (sb and sb.CreateTexture) then return end

    if frame._msufPlayerChannelStripes then return end

    local stripes = {}
    for i = 1, 5 do
        local t = sb:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)
		-- Always fully visible (no progress-based reveal).
		if t.SetAlpha then t:SetAlpha(1) end
        t:SetWidth(2)
        t:SetPoint("TOP", sb, "TOP", 0, 0)
        t:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
        t:Hide()
        stripes[i] = t
    end
    frame._msufPlayerChannelStripes = stripes

    if not frame._msufPlayerChannelStripesHooked and sb.HookScript then
        frame._msufPlayerChannelStripesHooked = true
        sb:HookScript("OnSizeChanged", function()
            -- Reposition on resize.
            if frame and frame._msufPlayerChannelStripes then
                frame._msufPlayerChannelStripesForce = true
            end
        end)
    end
end

local function MSUF__HidePlayerChannelHasteStripes(frame)
    local stripes = frame and frame._msufPlayerChannelStripes
    if not stripes then return end
    for i = 1, #stripes do
        local t = stripes[i]
        if t and t.Hide then t:Hide() end
    end
end

local function MSUF__UpdatePlayerChannelHasteStripes(frame, force)
    if not (frame and frame.unit == "player") then return end

    -- Respect the menu toggle; if disabled, force-hide stripes immediately.
    if not MSUF__IsChannelTickLinesEnabled() then
        MSUF__HidePlayerChannelHasteStripes(frame)
        frame._msufPlayerChannelStripesLastW = nil
        frame._msufPlayerChannelStripesLastFactor = nil
        return
    end

    -- Only on channels; never on empower.
    if not (frame.MSUF_isChanneled and not frame.isEmpower) then
        MSUF__HidePlayerChannelHasteStripes(frame)
        frame._msufPlayerChannelStripesLastW = nil
        frame._msufPlayerChannelStripesLastFactor = nil
        return
    end

    local sb = frame.statusBar
    if not (sb and sb.GetWidth) then return end

    MSUF__EnsurePlayerChannelHasteStripes(frame)
    local stripes = frame._msufPlayerChannelStripes
    if not stripes then return end

	local w = sb:GetWidth() or 0
	if w <= 1 then
		-- Bar width can be 0 on the very first frame; still show stripes immediately using a safe fallback
		-- and force a proper reposition on the next size update.
		w = frame._msufPlayerChannelStripesLastW or 200
		frame._msufPlayerChannelStripesForce = true
	end

    local haste = 0
    if type(UnitSpellHaste) == "function" then
        local ok, v = MSUF_FastCall(UnitSpellHaste, "player")
        if ok and type(v) == "number" then haste = v end
    end
    local factor = 1 + (haste / 100)
    if factor <= 0 then factor = 1 end

    if frame._msufPlayerChannelStripesForce then
        force = true
        frame._msufPlayerChannelStripesForce = nil
    end

    local lastW = frame._msufPlayerChannelStripesLastW
    local lastF = frame._msufPlayerChannelStripesLastFactor
    if not force and lastW == w and lastF == factor then
        return
    end
    frame._msufPlayerChannelStripesLastW = w
    frame._msufPlayerChannelStripesLastFactor = factor

    local rf = (frame._msufStripeReverseFill == true)
    local anchor = rf and "RIGHT" or "LEFT"

    -- Base divider 6 => 5 markers at 1/6..5/6 when haste==0. With haste, markers compress toward start.
    local div = 6
    for i = 1, 5 do
        local t = stripes[i]
        if t and t.SetPoint then
			if t.SetAlpha then t:SetAlpha(1) end
            local pos = (i / div) / factor
            if pos < 0.02 then pos = 0.02 end
            if pos > 0.98 then pos = 0.98 end
            local x = w * pos
            if rf then x = -x end
            t:ClearAllPoints()
            t:SetPoint("CENTER", sb, anchor, x, 0)
            t:Show()
        end
    end
end



-- Step 2 (DurationObjects): keep cast time text working without relying on secret duration values.
-- We derive remaining time from the StatusBar's animated value/min/max (timer-driven or manual).
local function MSUF__IsPlainNumber_SecretSafe(n)
    if type(n) ~= "number" then return false end
    -- Secret numbers can still report type=="number" but will throw on arithmetic/comparisons.
    local ok = pcall(function()
        local _ = n + 0
        local __ = (n > -1e308) -- force a comparison too
        return _ and __ ~= nil
    end)
    return ok
end

local function MSUF__ToNumber_SecretSafe(v)
    if v == nil then return nil end

    -- In Midnight/Beta, "secret numbers" can still report type(v) == "number" but will error on arithmetic/comparisons.
    -- Therefore: prefer ToPlain() when available, but STILL validate the result.
    if type(_G.ToPlain) == "function" then
        local ok, pv = pcall(_G.ToPlain, v)
        if ok then
            local n = tonumber(pv)
            if n ~= nil and MSUF__IsPlainNumber_SecretSafe(n) then
                return n
            end
        end
    end

    -- If it's a number, validate it via pcall arithmetic/comparison.
    if type(v) == "number" then
        if MSUF__IsPlainNumber_SecretSafe(v) then
            return v
        end
        return nil
    end

    -- Last resort: try tonumber on stringy values safely, then validate.
    local ok2, n2 = pcall(tonumber, v)
    if ok2 and n2 ~= nil and MSUF__IsPlainNumber_SecretSafe(n2) then
        return n2
    end
    return nil
end

local function MSUF__GetRemainingFromStatusBar(frame)
    local sb = frame and frame.statusBar
    if not (sb and sb.GetValue and sb.GetMinMaxValues) then return nil end

    local okV, v = MSUF_FastCall(sb.GetValue, sb)
    if not okV then return nil end

    local okMM, minV, maxV = MSUF_FastCall(sb.GetMinMaxValues, sb)
    if not okMM then return nil end

    v    = MSUF__ToNumber_SecretSafe(v)
    minV = MSUF__ToNumber_SecretSafe(minV)
    maxV = MSUF__ToNumber_SecretSafe(maxV)

    if not (v and minV and maxV) then return nil end
    local span = maxV - minV
    if not (type(span) == "number" and span > 0) then return nil end

    -- Heuristic: if value decreases across ticks, treat value as "remaining".
    -- Otherwise treat (max - value) as remaining. This handles differing timer directions.
    local last = frame._msufLastSBValue
    frame._msufLastSBValue = v
    local decreasing = (last ~= nil and v < (last - 0.0001))

    local rem = decreasing and (v - minV) or (maxV - v)
    if type(rem) ~= "number" then return nil end
    if rem < 0 then rem = 0 end
    return rem
end

function _G.MSUF_UpdateCastTimeText_FromStatusBar(frame)
    if not (frame and frame.timeText) then return end

    if not (type(MSUF_IsCastTimeEnabled) == "function" and MSUF_IsCastTimeEnabled(frame)) then
        MSUF_SetTextIfChanged(frame.timeText, "")
        return
    end

    local rem = MSUF__GetRemainingFromStatusBar(frame)
    if type(rem) == "number" then
        MSUF_SetCastTimeText(frame, rem)
    else
        MSUF_SetTextIfChanged(frame.timeText, "")
    end
end


-- Empower timeline helpers (non-player units)
-- NOTE: Disabled. For target/focus/boss we treat EMPOWER as a normal CAST/CHANNEL using duration objects only.

local function MSUF_ClearEmpowerState(frame)
    if not frame then return end
    frame.isEmpower = nil
    frame.empowerStartTime = nil
    frame.empowerStageEnds = nil
    frame.empowerTotalBase = nil
    frame.empowerTotalWithGrace = nil
    frame.empowerNextStage = nil
    frame.MSUF_empowerLayoutPending = nil
    frame.MSUF_wantsEmpower = nil
    frame.MSUF_empowerRetryCount = nil
    frame.MSUF_empowerRetryActive = nil

    if frame.empowerTicks then
        for i = 1, #frame.empowerTicks do
            local t = frame.empowerTicks[i]
            if t then
                t:Hide()
                if t.MSUF_glow then t.MSUF_glow:Hide() end
                if t.MSUF_flash then t.MSUF_flash:Hide() end
            end
        end
    end
    if frame.empowerSegments then
        for i = 1, #frame.empowerSegments do
            local s = frame.empowerSegments[i]
            if s then s:Hide() end
        end
    end
end

local function CreateCastBar(name, unit)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetClampedToScreen(true)
    frame.unit = unit
    frame.reverseFill = false -- legacy flag; actual fill controlled via MSUF_GetCastbarReverseFill()

    function frame:UpdateColorForInterruptible()
        if not self or not self.statusBar or not self.statusBar.SetStatusBarColor then
            return
        end

        EnsureDB()
        local g = MSUF_DB and MSUF_DB.general or {}

		-- IMPORTANT (Midnight/Beta, secret-safe):
		-- Do NOT probe nameplate castBar.barType here. It can be a *secret string* and ANY comparison
		-- ("==", "~=") may hard-error.
		-- We rely solely on:
		--   1) UnitCastingInfo/UnitChannelInfo pass-through (state.apiNotInterruptibleRaw -> self._msufApiNotInterruptibleRaw)
		--   2) UNIT_SPELLCAST_(NOT_)INTERRUPTIBLE events updating self.isNotInterruptible (plain boolean)
		local isNonInterruptible = (self.isNotInterruptible == true)

	        -- Resolve BOTH colors (interruptible + non-interruptible). We then apply the tint using
	        -- Texture:SetVertexColorFromBoolean(rawNotInterruptible, nonIntColor, intColor) when available.
	        -- IMPORTANT: rawNotInterruptible may be a *secret value* => never boolean-test it in Lua.
	        local nr, ng, nb
	        if MSUF_GetNonInterruptibleCastColor then
	            nr, ng, nb = MSUF_GetNonInterruptibleCastColor()
	        end
	        if not (nr and ng and nb) then
	            local key = g.castbarNonInterruptibleColor or "red"
	            local __c = (type(MSUF_GetColorFromKey) == "function") and MSUF_GetColorFromKey(key) or nil
	            if __c and __c.GetRGB then
	                nr, ng, nb = __c:GetRGB()
	            end
	        end
	        if not (nr and ng and nb) then
	            nr, ng, nb = 1, 0, 0
	        end

	        local ir, ig, ib
	        if MSUF_GetInterruptibleCastColor then
	            ir, ig, ib = MSUF_GetInterruptibleCastColor()
	        end
	        if not (ir and ig and ib) then
	            local key = g.castbarInterruptibleColor or "turquoise"
	            local __c = (type(MSUF_GetColorFromKey) == "function") and MSUF_GetColorFromKey(key) or nil
	            if __c and __c.GetRGB then
	                ir, ig, ib = __c:GetRGB()
	            end
	        end
	        if not (ir and ig and ib) then
	            ir, ig, ib = 0.2, 0.8, 0.8
	        end

	        local rawNI = self._msufApiNotInterruptibleRaw
	        if isNonInterruptible then
	            -- Safe override (nameplate shield / event-driven) should always win.
	            rawNI = true
	        end

	        if type(_G.MSUF_Castbar_ApplyNonInterruptibleTint) == "function" then
	            _G.MSUF_Castbar_ApplyNonInterruptibleTint(self, rawNI, nr, ng, nb, 1, ir, ig, ib, 1, isNonInterruptible)
	        else
	            if isNonInterruptible then
	                _G.MSUF_SetStatusBarColorIfChanged(self.statusBar, nr, ng, nb, 1)
	            else
	                _G.MSUF_SetStatusBarColorIfChanged(self.statusBar, ir, ig, ib, 1)
	            end
	        end
    end

    
    -- Step 8 (Engine integration): build cast state once (Unit APIs) and feed it into :Cast(state)
    -- so we don't call UnitCastingInfo/UnitChannelInfo twice per event/timer.
    local function MSUF_Driver_BuildCastStateFor(self)
        local E = (_G.MSUF_GetCastbarEngine and _G.MSUF_GetCastbarEngine()) or nil
        if E and E.BuildState then
            return E:BuildState(self.unit, self)
        end
        return nil
    end

    -- Step 4 (accuracy, secret-safe): track a numeric cast identity to ignore stale STOP/FAILED events
    -- without relying on castGUID (which may be a secret value in Midnight/Beta).
    -- Identity is OPTIONAL: we only gate when we have numeric values (spellId and/or spellSequenceID).
    local function MSUF_Driver_SetActiveIdentity(self, st)
        if not self then return end
        if st and st.active then
            self._msufActiveSeq = st.spellSequenceID
            self._msufActiveCastType = st.castType
        else
            self._msufActiveSeq = nil
            self._msufActiveCastType = nil
        end
    end

    local function MSUF_Driver_IsStaleStop(self, snapSeq)
        if not self then return false end
        -- We ONLY gate on spellSequenceID because spellID/castGUID may be secret values on Midnight/Beta.
        -- If sequence IDs are not available on this build (nil), gating is disabled (safe fallback).
        if snapSeq == nil then return false end
        local curSeq = self._msufActiveSeq
        if curSeq == nil then return false end
        -- Only compare plain numbers (sequence is designed to be non-secret).
        if type(snapSeq) ~= 'number' or type(curSeq) ~= 'number' then return false end
        return curSeq ~= snapSeq
    end

    local function MSUF_Driver_CastResync(self)
        -- During INTERRUPTED feedback hold, ignore further resync events (STOP/CHANNEL_STOP etc.)
        -- so we don't clear the \"Interrupted\" text or restart timer-driven animations.
        if self.interrupted then
            return
        end
        local st = MSUF_Driver_BuildCastStateFor(self)
        MSUF_Driver_SetActiveIdentity(self, st)
        self:Cast(st)
    end


    -- CHANNEL_STOP can fire as part of a "channel refresh" when the same spell is pressed again while channeling.
    -- In that case, UNIT_SPELLCAST_CHANNEL_START often follows immediately. If we treat CHANNEL_STOP as terminal
    -- instantly, target/focus bars will blink / end too early. However, on some builds UnitChannelInfo can also
    -- return stale data briefly after the channel actually ended, which can "restart" the bar if we resync.
    --
    -- Strategy:
    -- 1) On CHANNEL_START, bump a token.
    -- 2) On CHANNEL_STOP, queue a deferred confirm. If a new CHANNEL_START happened (token changed), we do nothing.
    -- 3) If the unit is still channeling (UnitChannelInfo), treat this as refresh/event-ordering and resync once;
    --    only hard-stop when channel info is absent after a short settle.


    -- Step 6g: token-based stop confirm (fixes target/focus channel refresh + prevents lingering)
    local function MSUF_Driver_CancelStopConfirm(self)
        if not self then return end
        local t
        t = self._msufStopTimer1; if t and t.Cancel then t:Cancel() end; self._msufStopTimer1 = nil
        t = self._msufStopTimer2; if t and t.Cancel then t:Cancel() end; self._msufStopTimer2 = nil
        t = self._msufStopTimer3; if t and t.Cancel then t:Cancel() end; self._msufStopTimer3 = nil
    end

    local function MSUF_Driver_BumpCastToken(self)
        self._msufCastToken = (self._msufCastToken or 0) + 1
        return self._msufCastToken
    end

	-- IMPORTANT (Midnight/Beta): castGUID may be "secret" and comparing it can hard-error.
	-- We do *not* key on castGUID at all. The stop-confirm logic below is purely token/state based.
	local function MSUF_Driver_QueueStopConfirm(self, kind)
        if not self or self.interrupted then return end
        local token = self._msufCastToken or 0
        local snapSeq = self._msufActiveSeq
        MSUF_Driver_CancelStopConfirm(self)

	    if kind == "CHANNEL" then
	        -- Channels can do STOP -> (gap) -> START on refresh. The gap can be as large as SpellQueueWindow.
	        -- If we kill too early, spamming/queueing can "cut" the visible channel mid-cast.
	        local qms = 0
	        if GetCVar then qms = tonumber(GetCVar("SpellQueueWindow") or "0") or 0 end
	        if qms < 0 then qms = 0 end
	        local settle = (qms / 1000) + 0.08
	        if settle < 0.20 then settle = 0.20 end
	        if settle > 0.70 then settle = 0.70 end
	
	        local fast = 0.12
	        if fast > settle then fast = settle end
	        local t2 = settle - fast
	        if t2 < 0.08 then t2 = 0.08 end
	
	        -- Absolute failsafe: never allow a channel to keep animating forever after a STOP.
	        local failsafe = settle + 0.55
	        if failsafe < 0.70 then failsafe = 0.70 end
	        if failsafe > 1.20 then failsafe = 1.20 end
	
	        self._msufStopTimer1 = C_Timer.NewTimer(fast, function()
	            if not self or self.interrupted then return end
	            if (self._msufCastToken or 0) ~= token then return end
	
	            -- If the unit is channeling again, treat as refresh.
	            local st = MSUF_Driver_BuildCastStateFor(self)
	            if st and st.active then MSUF_Driver_SetActiveIdentity(self, st); self:Cast(st); return end
	
	            -- If this STOP belongs to an older cast (spellId/sequence changed), ignore it.
	            if MSUF_Driver_IsStaleStop(self, snapSeq) then
	                MSUF_Driver_CastResync(self)
	                return
	            end
	
	            -- Confirm again after the settle window (covers SQW refresh gaps).
	            self._msufStopTimer2 = C_Timer.NewTimer(t2, function()
	                if not self or self.interrupted then return end
	                if (self._msufCastToken or 0) ~= token then return end
	
	                local st2 = MSUF_Driver_BuildCastStateFor(self)
	                if st2 and st2.active then MSUF_Driver_SetActiveIdentity(self, st2); self:Cast(st2); return end
	
	                if MSUF_Driver_IsStaleStop(self, snapSeq) then
	                    MSUF_Driver_CastResync(self)
	                    return
	                end
	                self:SetSucceeded()
	            end)
	        end)
	
	        self._msufStopTimer3 = C_Timer.NewTimer(failsafe, function()
	            if not self or self.interrupted then return end
	            if (self._msufCastToken or 0) ~= token then return end
	
	            local st = MSUF_Driver_BuildCastStateFor(self)
	            if st and st.active then
	                MSUF_Driver_SetActiveIdentity(self, st)
	                self:Cast(st)
	                return
	            end
	
	            if MSUF_Driver_IsStaleStop(self, snapSeq) then
	                MSUF_Driver_CastResync(self)
	                return
	            end
	            self:SetSucceeded()
	        end)
	        return
	    end

        -- Normal casts/empower: short confirm, but resync if something new is active.
        self._msufStopTimer1 = C_Timer.NewTimer(0.12, function()
            if not self or self.interrupted then return end
            if (self._msufCastToken or 0) ~= token then return end
            local st = MSUF_Driver_BuildCastStateFor(self)
            if st and st.active then
                MSUF_Driver_SetActiveIdentity(self, st)
                self:Cast(st)
            else
                if MSUF_Driver_IsStaleStop(self, snapSeq) then
                    MSUF_Driver_CastResync(self)
                    return
                end
                self:SetSucceeded()
            end
        end)

        -- Defensive failsafe.
        self._msufStopTimer3 = C_Timer.NewTimer(0.40, function()
            if not self or self.interrupted then return end
            if (self._msufCastToken or 0) ~= token then return end
            if MSUF_Driver_IsStaleStop(self, snapSeq) then
                MSUF_Driver_CastResync(self)
                return
            end
            self:SetSucceeded()
        end)
    end

frame:SetScript("OnEvent", function(self, event, arg1, ...)
        local _, spellID = ...
        if not MSUF_Driver_IsCastbarEnabled(self.unit or "") then
            MSUF_Driver_CancelStopConfirm(self)
            MSUF__HidePlayerChannelHasteStripes(self)
            _G.MSUF_CB_ResetStateOnStop(self, "HARDHIDE")
            return
        end

-- Empower handling:
--   Player: keep full empower pipeline (stages/lines) via MSUF_wantsEmpower.
--   Non-player (target/focus/boss): NEVER enter empower pipeline. Treat EMPOWER_* as normal CAST events and use duration objects only.
if self.unit == "player" then
    if event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        self.MSUF_wantsEmpower = true
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        self.MSUF_wantsEmpower = nil
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- Non-empower start/channel: clear any prior empower intent.
        self.MSUF_wantsEmpower = nil
    end
else
    -- Hard-disable empower mode for non-player units.
    self.MSUF_wantsEmpower = nil
    if event == "UNIT_SPELLCAST_EMPOWER_START" then
        event = "UNIT_SPELLCAST_START"
    elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        event = "UNIT_SPELLCAST_DELAYED"
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        event = "UNIT_SPELLCAST_STOP"
    end
end

        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
            MSUF_Driver_CancelStopConfirm(self)
            local tok = MSUF_Driver_BumpCastToken(self)
            self.isNotInterruptible = false
            MSUF_Driver_CastResync(self)
            -- Retry once shortly after start to handle the tiny "info not ready yet" window on target/focus channels.
            C_Timer.After(0.05, function()
                if not self or self.interrupted then return end
                if (self._msufCastToken or 0) ~= tok then return end
                local st = MSUF_Driver_BuildCastStateFor(self)
                if st and st.active then
                    MSUF_Driver_SetActiveIdentity(self, st)
                    self:Cast(st)
                end
            end)

	        elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
            if event == "UNIT_SPELLCAST_CHANNEL_UPDATE" and (self._msufStopTimer1 or self._msufStopTimer2 or self._msufStopTimer3) then
                MSUF_Driver_CancelStopConfirm(self)
                MSUF_Driver_BumpCastToken(self)
            end
            MSUF_Driver_CastResync(self)

	        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
	            MSUF_Driver_QueueStopConfirm(self, "CAST")
            

	        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
	            MSUF_Driver_QueueStopConfirm(self, "CHANNEL")
            

	        elseif event == "UNIT_SPELLCAST_FAILED" then
	            MSUF_Driver_QueueStopConfirm(self, "CAST")

        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- NOTE: SUCCEEDED can fire while a channel is still running when the player re-queues/spams the same spell
            -- inside SpellQueueWindow. Never treat SUCCEEDED as terminal for the player castbar.
            if self.unit ~= "player" then
                MSUF_Driver_CastResync(self)
            else
                local st = MSUF_Driver_BuildCastStateFor(self)
                if st and st.active then
                    MSUF_Driver_SetActiveIdentity(self, st)
                    self:Cast(st)
                end
                -- else: ignore (prevents mid-channel "cut" when spamming/queueing)
            end

	        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
	            if arg1 ~= self.unit then return end
            -- Light fast-path: this event only changes interruptibility mid-cast.
            -- Do NOT resync the whole cast state (expensive + can cause jitter); just refresh visuals.
            self.isNotInterruptible = false
            self._msufApiNotInterruptibleRaw = false -- keep vertex-tint source in sync; plain boolean is safe.
            if self.UpdateColorForInterruptible then _G.MSUF_CB_ApplyColor(self) end

	        elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
	            if arg1 ~= self.unit then return end
            -- Light fast-path: see above.
            self.isNotInterruptible = true
            self._msufApiNotInterruptibleRaw = true
            if self.UpdateColorForInterruptible then _G.MSUF_CB_ApplyColor(self) end

	        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
	            if arg1 ~= self.unit then return end
            MSUF_Driver_CancelStopConfirm(self)
            self:SetInterrupted()

        elseif (event == "PLAYER_TARGET_CHANGED" and self.unit == "target")
            or (event == "PLAYER_FOCUS_CHANGED" and self.unit == "focus")
        then
            MSUF_Driver_CancelStopConfirm(self)
            MSUF_Driver_BumpCastToken(self)
            if self.timer then
                self.timer:Cancel()
                self.timer = nil
            end
            self.interrupted = nil
            MSUF_Driver_CastResync(self)
        end
    end)


    local function CreateCastFrame(self)
        if type(_G.MSUF_BuildCastbarFrameElements) == "function" then
            return _G.MSUF_BuildCastbarFrameElements(self)
        end
        if MSUF_DevPrint then MSUF_DevPrint("MSUF: MSUF_BuildCastbarFrameElements missing") end
    end

                -- Step 1 (cleanup): Legacy driver-side CastbarManager/update loop removed.
        -- The canonical CastbarManager + MSUF_RegisterCastbar/MSUF_UnregisterCastbar
        -- and MSUF_UpdateCastbarFrame live in MSUF_Castbars.lua.



function frame:Cast(preState)
        -- Step 5: Apply-state decoupling.
        -- Do NOT query UnitCastingInfo/UnitChannelInfo or Unit*Duration APIs here.
        -- The engine (MSUF_CastbarEngine:BuildState) is the single source of truth for unit queries.
        local state = preState
        if not (state and state.active and state.unit == self.unit and state.spellName) then
            local engine = _G.MSUF_GetCastbarEngine and _G.MSUF_GetCastbarEngine()
            if engine and engine.BuildState then
                state = engine:BuildState(self.unit, self)
            else
                state = nil
            end
        end

		    -- Capture the raw API notInterruptible flag for THIS cast.
		    -- It may be a *secret value* on Midnight/Beta, so we only store it and later pass it
		    -- into C-side helpers (never boolean-test it in Lua).
		    -- IMPORTANT: do NOT use "state and raw or nil" because "or" would boolean-test raw.
		    local rawNI = nil
		    if state ~= nil then
		        rawNI = state.apiNotInterruptibleRaw
		    end
		    self._msufApiNotInterruptibleRaw = rawNI

	        local spellName, text, texture, startTimeMS, endTimeMS
        local isChanneled = false

        if state and state.active and state.spellName then
            spellName = state.spellName
            text = state.text or state.spellName
            texture = state.icon
            startTimeMS = state.startTimeMS
            endTimeMS = state.endTimeMS
            isChanneled = (state.castType == "CHANNEL")
        end

-- Record non-secret identity bits (debug/future gating). Never compare castGUID.
	        if state and state.active then
	            self._msufCastSpellID = state.spellId
	            self._msufCastSpellSeq = state.spellSequenceID
	        end

        if self.hideTimer and self.hideTimer.Cancel then
            self.hideTimer:Cancel()
            self.hideTimer = nil
        end

        if self.succeededTimer and self.succeededTimer.Cancel then
            self.succeededTimer:Cancel()
            self.succeededTimer = nil
        end

        local durationObj = (state and state.durationObj ~= nil) and state.durationObj or nil

        -- Step 5: Duration objects are sourced exclusively from the engine.
        -- On some builds (target/focus channel refresh), durationObj can briefly be nil while the channel is still active.
        -- If we have a cached durationObj for the same spellSequenceID, reuse it to avoid one-tick gaps.
        if (durationObj == nil) and state and state.active then
            local seq = state.spellSequenceID
            if type(seq) == "number" and self._msufLastDurationSeq == seq and self._msufLastDurationObj ~= nil then
                durationObj = self._msufLastDurationObj
                state.durationObj = durationObj
            end
        end

        if state and state.active and durationObj ~= nil then
            local seq = state.spellSequenceID
            if type(seq) == "number" then
                self._msufLastDurationSeq = seq
                self._msufLastDurationObj = durationObj
            end
        elseif not (state and state.active) then
	            self._msufApiNotInterruptibleRaw = nil
            self._msufLastDurationSeq = nil
            self._msufLastDurationObj = nil
        end
-- Empower: Player-only.
-- For target/focus/boss we intentionally do NOT attempt empower stage rendering.
-- (Enemy empower stage APIs can yield secret values and are unreliable in Midnight/Beta.)
-- Ensure any leftover empower visuals are cleared before proceeding as a normal cast/channel.
if self.isEmpower then
    MSUF_ClearEmpowerState(self)
end

if spellName and durationObj then
            self.interrupted = nil

            if self.icon and texture then
                self.icon:SetTexture(texture)
            end

            if self.castText then
                _G.MSUF_CB_ApplyTexts(self, nil, text or spellName or "", nil)
            end

            self.MSUF_durationObj = durationObj
            self.MSUF_isChanneled = isChanneled

            -- Reset hard-stop persistence timers on a successful (re)start.
            self._msufHardStopNoChannelSince = nil
            self._msufHardStopNoCastSince = nil

            self.castDuration = nil
            self.castElapsed  = nil
            self.MSUF_timerDriven = nil
            self.MSUF_timerRangeSet = nil
            self._msufLastSBValue = nil
            self.MSUF_channelDirect = (isChanneled and (self.unit == "target" or self.unit == "focus")) and true or nil

            local okTimer = false
local __msuf_rf = nil
if type(_G.MSUF_BuildCastState) == "function" then
    local st = _G.MSUF_BuildCastState(self.unit, self)
    __msuf_rf = st and st.reverseFill
end
if __msuf_rf == nil then
    __msuf_rf = (type(_G.MSUF_GetCastbarReverseFillForFrame) == "function" and _G.MSUF_GetCastbarReverseFillForFrame(self, isChanneled)) or false
end
__msuf_rf = (__msuf_rf == true)

-- Player-only: remember reverseFill so stripe anchoring matches bar direction.
self._msufStripeReverseFill = __msuf_rf

-- Player-only: (re)compute channel haste stripes (positions depend on current haste + bar width).
MSUF__UpdatePlayerChannelHasteStripes(self, true)


if self.statusBar then
    if type(_G.MSUF_ApplyCastbarTimerDirection) == "function" then
        okTimer = _G.MSUF_ApplyCastbarTimerDirection(self.statusBar, durationObj, __msuf_rf)
    elseif type(_G.MSUF_SetStatusBarTimerDuration) == "function" then
        okTimer = _G.MSUF_SetStatusBarTimerDuration(self.statusBar, durationObj, __msuf_rf)
        if self.statusBar.SetReverseFill then
            MSUF_FastCall(self.statusBar.SetReverseFill, self.statusBar, (__msuf_rf and true or false))
        end
    elseif self.statusBar.SetTimerDuration then
        -- Cache which signature works (some builds expect a numeric direction, others a boolean).
        -- This avoids probing twice on every cast start.
        local mode = _G.__MSUF_TimerDurationMode
        if mode ~= nil then
            okTimer = MSUF_FastCall(self.statusBar.SetTimerDuration, self.statusBar, durationObj, mode)
        else
            okTimer = MSUF_FastCall(self.statusBar.SetTimerDuration, self.statusBar, durationObj, 0)
            if okTimer then
                _G.__MSUF_TimerDurationMode = 0
            else
                okTimer = MSUF_FastCall(self.statusBar.SetTimerDuration, self.statusBar, durationObj, true)
                if okTimer then
                    _G.__MSUF_TimerDurationMode = true
                end
            end
        end
        if self.statusBar.SetReverseFill then
            MSUF_FastCall(self.statusBar.SetReverseFill, self.statusBar, (__msuf_rf and true or false))
        end
    elseif self.statusBar.SetReverseFill then
        MSUF_FastCall(self.statusBar.SetReverseFill, self.statusBar, (__msuf_rf and true or false))
        okTimer = false
    end
end
self.MSUF_timerDriven = okTimer and true or false

            if self.UpdateColorForInterruptible then
                _G.MSUF_CB_ApplyColor(self)
            end

            if MSUF_RegisterCastbar then
                MSUF_RegisterCastbar(self)
            end

            if self.timeText then
                _G.MSUF_UpdateCastTimeText_FromStatusBar(self)
            end

            self:Show()
        else
if self.hideTimer and self.hideTimer.Cancel then
    self.hideTimer:Cancel()
end

self.hideTimer = C_Timer.NewTimer(0, function()
    if not self or not self.unit then return end

    local st = MSUF_Driver_BuildCastStateFor(self)
if st and st.active then
    self:Cast(st)
    return
end

    _G.MSUF_CB_ResetStateOnStop(self, "STOPPED")
end)
        end

        if self.timer then
            self.timer:Cancel()
            self.timer = nil
        end

        local grace = (_G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5)

        if type(grace) ~= "number" then grace = 0.5 end
        if grace < 0 then grace = 0 end

        self.timer = C_Timer.NewTimer(grace, function()
            if self.interrupted then
                self.interrupted = nil
                self:Hide()
            end
        end)
    end

function frame:SetInterrupted()
    MSUF__HidePlayerChannelHasteStripes(self)
    _G.MSUF_CB_ResetStateOnStop(self, "INTERRUPTED")
    self.interrupted = true
    self._msufApiNotInterruptibleRaw = nil

        -- Respect per-unit "Show interrupt" toggle (hide interrupt feedback entirely when disabled).
        EnsureDB()
        local conf = (self.unit and MSUF_DB and MSUF_DB[self.unit]) or nil
        if conf and conf.showInterrupt == false then
            self.interrupted = nil
            if self.castText then
                _G.MSUF_CB_ApplyTexts(self, nil, "", nil)
            end
            if self.timeText then
                _G.MSUF_CB_ApplyTexts(self, nil, nil, "")
            end
            self:Hide()
            return
        end


        if self.statusBar and self.statusBar.SetStatusBarColor then
            _G.MSUF_SetStatusBarColorIfChanged(self.statusBar, 1, 0, 0, 1)
        end

        if self.statusBar and self.statusBar.SetMinMaxValues then
            pcall(self.statusBar.SetMinMaxValues, self.statusBar, 0, 1)
        end
        if self.statusBar and self.statusBar.SetValue then
            pcall(self.statusBar.SetValue, self.statusBar, 1)
        end

        local rf = MSUF_GetCastbarReverseFillForFrame(self, false)
        if _G.MSUF_ApplyCastbarTimerDirection then
            _G.MSUF_ApplyCastbarTimerDirection(self.statusBar, nil, rf)
        elseif _G.MSUF_SetStatusBarReverseFill then
            _G.MSUF_SetStatusBarReverseFill(self.statusBar, rf)
        elseif self.statusBar and self.statusBar.SetReverseFill then
            pcall(self.statusBar.SetReverseFill, self.statusBar, rf and true or false)
        end

        if self.castText and self.castText.SetText then
            _G.MSUF_CB_ApplyTexts(self, nil, "Interrupted", nil)
        end

        if self.timeText and self.timeText.SetText then
            _G.MSUF_CB_ApplyTexts(self, nil, nil, "")
        end

        self:Show()

        if MSUF_PlayCastbarShake then
            MSUF_FastCall(MSUF_PlayCastbarShake, self)
        end

        local grace = (_G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5)

        if type(grace) ~= "number" then grace = 0.5 end
        if grace < 0 then grace = 0 end
        if self._msufCastState then
            local __t = (type(GetTime) == "function") and GetTime() or 0
            local __st = self._msufCastState
            __st.unit = self.unit
            __st.key = self._msufBarKey or self.unit
            __st.active = false
            __st.phase = "INTERRUPT"
            __st.durationObj = nil
            __st.holdUntil = __t + grace
        end

        self.hideTimer = C_Timer.NewTimer(grace, function()
            if not self or not self.unit then return end
            local st = MSUF_Driver_BuildCastStateFor(self)
            if st and st.active then
                self.interrupted = nil
                self:Cast(st)
                return
            end

            if self.interrupted then
                self.interrupted = nil
                self:Hide()
            end
        end)

    end

function frame:SetSucceeded()
    MSUF__HidePlayerChannelHasteStripes(self)

    -- If we're in interrupt feedback state, do NOT cancel the interrupt hold timer.
    -- Successful interrupts usually fire INTERRUPTED followed by STOP; STOP would call SetSucceeded.
    if self.interrupted then
        return
    end

    _G.MSUF_CB_ResetStateOnStop(self, "SUCCEEDED")
end

    frame:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", unit)

    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", unit)

    frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", unit)

    frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    frame:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")

    frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)

    if unit == "target" or unit == "focus" then
        frame:RegisterEvent("PLAYER_" .. unit:upper() .. "_CHANGED")
    end

    local msufFrame = _G["MSUF_" .. unit]
    if msufFrame then
        frame:ClearAllPoints()
        if unit == "target" then
            frame:SetPoint("BOTTOMLEFT", msufFrame, "TOPLEFT", 0, 5)
        elseif unit == "focus" then
            frame:SetPoint("TOPLEFT", msufFrame, "BOTTOMLEFT", 0, -5)
        elseif unit == "player" then
            frame:SetPoint("BOTTOM", msufFrame, "TOP", 0, 5)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, -300)
        end

        local w = msufFrame:GetWidth()
        if w and w > 0 then
            frame:SetWidth(w)
        end
    end

    CreateCastFrame(frame)
    frame:Hide()

    if unit == "target" then
        MSUF_TargetCastbar = frame
        _G.MSUF_TargetCastBar = frame
    elseif unit == "focus" then
        MSUF_FocusCastbar = frame
        _G.MSUF_FocusCastBar = frame
    elseif unit == "player" then
        MSUF_PlayerCastbar = frame
        _G.MSUF_PlayerCastBar = frame
    end

    return frame
end


function MSUF_EnsureCastbarManager()
    -- Step 1 (cleanup): no driver-side manager creation or Update wrapping.
    -- MSUF_Castbars.lua owns the manager. This function remains as a compatibility no-op.
    if MSUF_CastbarManager and MSUF_RegisterCastbar and MSUF_UnregisterCastbar and MSUF_UpdateCastbarFrame then
        return
    end
    -- If called before MSUF_Castbars.lua loads, it will become available later in the same addon.
end


MSUF_PlayerCastbar = MSUF_PlayerCastbar or nil -- forward declaration (shared global)


function MSUF_CastbarDriver_OnLogin(event)
        if not _G["TargetCastBar"] then
            CreateCastBar("TargetCastBar", "target")
        end
        if not _G["FocusCastBar"] then
            CreateCastBar("FocusCastBar", "focus")
        end

        if MSUF_ReanchorTargetCastBar then MSUF_ReanchorTargetCastBar() end
        if MSUF_ReanchorFocusCastBar  then MSUF_ReanchorFocusCastBar()  end
        if MSUF_ReanchorPlayerCastBar then MSUF_ReanchorPlayerCastBar() end
        if MSUF_UpdateCastbarVisuals  then MSUF_UpdateCastbarVisuals()  end
        if MSUF_UpdateCastbarTextures then MSUF_UpdateCastbarTextures() end

end

function MSUF_CastbarDriver_OnEnteringWorld(event)
        if TargetFrameSpellBar then
            TargetFrameSpellBar:UnregisterAllEvents()
            TargetFrameSpellBar:Hide()
            TargetFrameSpellBar:HookScript("OnShow", function(bar)
                bar:Hide()
            end)
        end

        if FocusFrameSpellBar then
            FocusFrameSpellBar:UnregisterAllEvents()
            FocusFrameSpellBar:Hide()
            FocusFrameSpellBar:HookScript("OnShow", function(bar)
                bar:Hide()
            end)
        end

        if PetCastingBarFrame then
            PetCastingBarFrame:UnregisterAllEvents()
            PetCastingBarFrame:Hide()
            PetCastingBarFrame:HookScript("OnShow", function(bar)
                bar:Hide()
            end)
        end

        if MSUF_EventBus_Unregister then
            MSUF_EventBus_Unregister("PLAYER_ENTERING_WORLD", "MSUF_CASTBAR_DRIVER_WORLD")
        end
end

MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_CASTBAR_DRIVER_LOGIN", MSUF_CastbarDriver_OnLogin, nil, true)
MSUF_EventBus_Register("PLAYER_ENTERING_WORLD", "MSUF_CASTBAR_DRIVER_WORLD", MSUF_CastbarDriver_OnEnteringWorld)

-- Optional export (debug / other modules)
_G.MSUF_CreateCastBar = CreateCastBar
