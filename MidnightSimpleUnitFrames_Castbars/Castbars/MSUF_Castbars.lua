-- MSUF_Castbars.lua

local addonName, ns = ...

-- Midnight/Beta: some sub-addons run in isolated environments.
-- Ensure the texture getter exists in THIS addon environment.
if type(MSUF_GetCastbarTexture) ~= "function" then
    local tostring = tostring
    local DEFAULT_TEX = "Interface\\TARGETINGFRAME\\UI-StatusBar"
    local texCache = {}

    function MSUF_GetCastbarTexture()
        local db = MSUF_DB
        local g  = db and db.general
        local castKey = g and g.castbarTexture or nil
        local barKey  = g and g.barTexture or nil

        local ck = tostring(castKey or "") .. "|" .. tostring(barKey or "")
        local hit = texCache[ck]
        if hit then return hit end

        local lsm = (ns and ns.LSM) or (LibStub and LibStub("LibSharedMedia-3.0", true))
        local tex

        if castKey and castKey ~= "" and lsm and lsm.Fetch then
            tex = lsm:Fetch("statusbar", castKey)
        end
        if (not tex or tex == "") and barKey and barKey ~= "" and lsm and lsm.Fetch then
            tex = lsm:Fetch("statusbar", barKey)
        end
        if not tex or tex == "" then
            tex = DEFAULT_TEX
        end

-- Midnight/Beta isolated environments: ensure small shared helpers exist in this addon scope.
local ROOT_G = (getfenv and getfenv(0)) or _G

if type(MSUF_SetTextIfChanged) ~= "function" then
    function MSUF_SetTextIfChanged(fs, txt)
        if not fs then return end
        -- Secret-safe: avoid comparing existing text; just set.
        fs:SetText(txt or "")
    end
end

if type(MSUF_SetPointIfChanged) ~= "function" then
    function MSUF_SetPointIfChanged(frame, point, relativeTo, relativePoint, xOfs, yOfs)
        if not frame then return end
        xOfs = xOfs or 0
        yOfs = yOfs or 0

        local snap = _G.MSUF_Snap
        if type(snap) == "function" then
            xOfs = snap(frame, xOfs)
            yOfs = snap(frame, yOfs)
        end

        if frame._msufLastPoint == point and frame._msufLastRel == relativeTo and frame._msufLastRelPoint == relativePoint
           and frame._msufLastX == xOfs and frame._msufLastY == yOfs then
            return
        end

        frame:ClearAllPoints()
        frame:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)

        frame._msufLastPoint = point
        frame._msufLastRel = relativeTo
        frame._msufLastRelPoint = relativePoint
        frame._msufLastX = xOfs
        frame._msufLastY = yOfs
    end
end

-- Export into real globals too (other modules may look there)
ROOT_G.MSUF_SetTextIfChanged = MSUF_SetTextIfChanged
ROOT_G.MSUF_SetPointIfChanged = MSUF_SetPointIfChanged
_G.MSUF_SetTextIfChanged = MSUF_SetTextIfChanged
_G.MSUF_SetPointIfChanged = MSUF_SetPointIfChanged


        texCache[ck] = tex
        return tex
    end
end


-- NOTE:
-- - EnsureDB() and MSUF_DB live in the core addon and are required here.
-- - UnitFrames table is created in MidnightSimpleUnitFrames.lua and exported as _G.MSUF_UnitFrames.
--   This file is intended to load AFTER MidnightSimpleUnitFrames.lua in the TOC.

local UnitFrames = _G.MSUF_UnitFrames

-- Fallback exports: these helpers used to live as local functions in the core file.
-- After refactoring castbars out, they must be available as globals for this module.
-- We define them here only if they are not already provided by the core (safety / load-order robustness).

if not _G.MSUF_IsCastbarEnabledForUnit then
    function _G.MSUF_IsCastbarEnabledForUnit(unit)
        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}

        if unit == "player" then
            return g.enablePlayerCastbar ~= false
        elseif unit == "target" then
            return g.enableTargetCastbar ~= false
        elseif unit == "focus" then
            return g.enableFocusCastbar ~= false
        end

        return true
    end
end

if not _G.MSUF_IsCastTimeEnabled then
    function _G.MSUF_IsCastTimeEnabled(frame)
        if not frame or not frame.unit then
            return true
        end
        EnsureDB()
        local g = MSUF_DB and MSUF_DB.general
        if not g then
            return true
        end

        local u = frame.unit
        if u == "player" then
            return g.showPlayerCastTime ~= false
        elseif u == "target" then
            return g.showTargetCastTime ~= false
        elseif u == "focus" then
            return g.showFocusCastTime ~= false
        end
        return true
    end
end


-- Empower stage blink helpers (used by empowered castbar stage tick flash).
-- Important: must exist even if the CastbarManager already exists (load-order / merge safety).
if not _G.MSUF_IsEmpowerStageBlinkEnabled then
    function _G.MSUF_IsEmpowerStageBlinkEnabled()
        if type(EnsureDB) == "function" then
            EnsureDB()
        end
        local g = MSUF_DB and MSUF_DB.general
        -- default ON (unless explicitly disabled)
        return (not g) or (g.empowerStageBlink ~= false)
    end
end

if not _G.MSUF_GetEmpowerStageBlinkTime then
    function _G.MSUF_GetEmpowerStageBlinkTime()
        if type(EnsureDB) == "function" then
            EnsureDB()
        end
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local v = tonumber(g.empowerStageBlinkTime)
        if not v then v = 0.14 end
        if v < 0.05 then v = 0.05 end
        if v > 1.00 then v = 1.00 end
        return v
    end
end

local MSUF_GetAnchorFrame = _G.MSUF_GetAnchorFrame


local function MSUF_PlayerCastbar_UpdateLatencyZone(self, isChanneled, durSec)
    if not self or not self.latencyBar or not self.statusBar then
        return
    end

    -- Honor Options -> Castbars -> Style -> Show latency indicator (default ON)
    EnsureDB()
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
            local reverse = MSUF_GetCastbarReverseFillForFrame(self, isChan)
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

    local reverse = MSUF_GetCastbarReverseFillForFrame(self, isChanneled)
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

    EnsureDB()
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

    local isNonInterruptible = falselocal unit = self.unit or "player"

local sec = (type(issecure) == "function") and issecure() or false
local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit, sec)

if nameplate then
    local bar = (nameplate.UnitFrame and nameplate.UnitFrame.castBar)
        or nameplate.castBar
        or nameplate.CastBar

    -- Secret-safe: bar.barType can be a secret string in Midnight/Beta.
    -- Never compare it directly in Lua. Only compare a plain copy via ToPlain (if available).
    local barType = bar and bar.barType
    local btPlain = nil
    if barType ~= nil and type(_G.ToPlain) == "function" then
        btPlain = _G.ToPlain(barType)
    end

    if btPlain == "uninterruptable"
        or btPlain == "uninterruptible"
        or btPlain == "uninterruptibleSpell"
        or btPlain == "shield"
    then
        isNonInterruptible = true
    end
end

    if self.isNotInterruptible then
        isNonInterruptible = true
    end

    local r, gCol, b, a

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
    EnsureDB()
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

    EnsureDB()
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

    self.statusBar:SetMinMaxValues(0, 1)
    self.statusBar:SetValue(0.8)

    local rf = MSUF_GetCastbarReverseFillForFrame(self, false)
    if _G.MSUF_ApplyCastbarTimerDirection then
        _G.MSUF_ApplyCastbarTimerDirection(self.statusBar, nil, rf)
    else
        self.statusBar:SetReverseFill(rf)
    end


    if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
        _G.MSUF_SetStatusBarColorIfChanged(self.statusBar, 0.8, 0.1, 0.1, 1)
    else
        self.statusBar:SetStatusBarColor(0.8, 0.1, 0.1, 1)
    end

    if self.castText then
        MSUF_SetTextIfChanged(self.castText, label or INTERRUPTED)
    end

    self:Show()
    self:SetAlpha(1)

    if MSUF_PlayCastbarShake then
        MSUF_FastCall(MSUF_PlayCastbarShake, self)
    end

    local grace = MSUF_PLAYER_INTERRUPT_FEEDBACK_DURATION
    if type(grace) ~= 'number' then grace = 0.5 end
    if grace < 0 then grace = 0 end

    self.hideTimer = C_Timer.NewTimer(grace, MSUF_PlayerCastbar_HideIfNoLongerCasting)
    self.hideTimer.msuCastbarFrame = self
end

local function MSUF_Empower_NormalizeSeconds(v)
    v = tonumber(v)
    if not v then return nil end
    if v > 20 then
        v = v / 1000
    end
    return v
end

local function MSUF_BuildEmpowerTimeline(unit)
    local stageEnds = {}
    local totalStage = 0

    local function getStageDur(idx)
        if type(GetUnitEmpowerStageDuration) ~= "function" then return nil end
        local ok, raw = MSUF_FastCall(GetUnitEmpowerStageDuration, unit, idx)
        if not ok then raw = nil end
        local d = MSUF_Empower_NormalizeSeconds(raw)
        if not d or d <= 0 then return nil end
        return d
    end

    local stageCount = nil
    if type(GetUnitEmpowerStageCount) == "function" then
        local ok, c = MSUF_FastCall(GetUnitEmpowerStageCount, unit)
        if ok then
            c = tonumber(c)
            if c and c > 0 then stageCount = c end
        end
    end

    local zeroBased = (getStageDur(0) ~= nil)
    local base = zeroBased and 0 or 1

    if stageCount then
        for stage = 1, stageCount do
            local idx = zeroBased and (stage - 1) or stage
            local d = getStageDur(idx)
            if not d then break end
            totalStage = totalStage + d
            stageEnds[#stageEnds + 1] = totalStage
        end
    else
        for i = base, base + 9 do
            local d = getStageDur(i)
            if not d then break end
            totalStage = totalStage + d
            stageEnds[#stageEnds + 1] = totalStage
        end
    end

    local maxHold = 0
    if type(GetUnitEmpowerHoldAtMaxTime) == "function" then
        local ok, raw = MSUF_FastCall(GetUnitEmpowerHoldAtMaxTime, unit)
        if not ok then raw = nil end
        maxHold = MSUF_Empower_NormalizeSeconds(raw) or 0
        if maxHold < 0 then maxHold = 0 end
    end

    local castTotal, castStartSec, castEndSec = nil, nil, nil
    if type(UnitCastingInfo) == "function" then
        local ok, _, _, _, startMS, endMS = MSUF_FastCall(UnitCastingInfo, unit)
        if ok and startMS and endMS and endMS > startMS then
            castStartSec = startMS / 1000
            castEndSec   = endMS / 1000
            castTotal    = (endMS - startMS) / 1000
        end
    end

    local totalBase = totalStage + maxHold

    if castTotal and castTotal > 0 then
        if totalBase <= 0 then
            totalBase = castTotal
        else
            if castTotal > totalBase then
                totalBase = castTotal
            end
        end

        if totalStage > 0 then
            local inferredHold = castTotal - totalStage
            if inferredHold < 0 then inferredHold = 0 end
            if maxHold <= 0 or math.abs((maxHold or 0) - inferredHold) > 0.15 then
                maxHold = inferredHold
            end
        end
    end

    if not totalBase or totalBase <= 0 then
        totalBase = 3.0
    end

    local grace = 0
    local totalWithGrace = totalBase
    if totalWithGrace <= 0 then totalWithGrace = 0.01 end

    return {
        stageEnds      = stageEnds,     -- lines for each stage end (includes max stage as last entry)
        totalStage     = totalStage,    -- end of last stage (without hold)
        maxHold        = maxHold,       -- hold at max stage (api or inferred)
        totalBase      = totalBase,     -- bar length (>= real cast window)
        totalWithGrace = totalWithGrace,
        grace          = grace,
        castStartSec   = castStartSec,
        castEndSec     = castEndSec,
        castTotal      = castTotal,
        zeroBased      = zeroBased,
        stageCount     = stageCount,
    }
end

local MSUF_EMPOWER_TICK_BASE_ALPHA        = 0.85  -- normal tick alpha
local MSUF_EMPOWER_TICK_BLINK_PEAK_ALPHA  = 1.00  -- tick alpha during blink (peak)
local MSUF_EMPOWER_TICK_BLINK_IN          = 0.06  -- seconds (fade in)
local MSUF_EMPOWER_TICK_BLINK_OUT         = 0.14  -- seconds (fade out)

local MSUF_EMPOWER_TICK_GLOW_WIDTH        = 12    -- px width of glow overlay
local MSUF_EMPOWER_TICK_GLOW_PEAK_ALPHA   = 0.90  -- glow alpha at peak
local MSUF_EMPOWER_TICK_FLASH_WIDTH        = 4     -- px width during flash (tick thickens)
local MSUF_EMPOWER_TICK_FLASH_TIME_DEFAULT      = 0.14  -- default seconds the red flash stays visible
local MSUF_EMPOWER_TICK_GLOW_COLOR        = {1.00, 0.85, 0.25} -- warm yellow

local function MSUF_GetEmpowerStageBlinkTime()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general
    local v = g and g.empowerStageBlinkTime
    if type(v) ~= "number" then
        v = MSUF_EMPOWER_TICK_FLASH_TIME_DEFAULT or 0.14
    end
    if v < 0.05 then v = 0.05 end
    if v > 1.00 then v = 1.00 end
    return v
end

local function MSUF_IsEmpowerStageBlinkEnabled()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general
    return (not g) or (g.empowerStageBlink ~= false)
end

local function MSUF_EnsureEmpowerTicks(frame, count)
    if not frame or not frame.statusBar then return end
    frame.empowerTicks = frame.empowerTicks or {}

    local h = frame.statusBar:GetHeight() or 18

    for i = 1, count do
        local tick = frame.empowerTicks[i]
        if not tick then
            tick = frame.statusBar:CreateTexture(nil, "OVERLAY")
            tick:SetTexture("Interface/Buttons/WHITE8x8")
            tick:SetVertexColor(1, 1, 1, MSUF_EMPOWER_TICK_BASE_ALPHA)
            tick:SetWidth(2)
            tick.MSUF_baseAlpha = MSUF_EMPOWER_TICK_BASE_ALPHA
            tick.MSUF_baseWidth = 2
            frame.empowerTicks[i] = tick
        end

        tick:SetHeight(h)
        tick:Show()

        if not tick.MSUF_flash then
            local flash = frame.statusBar:CreateTexture(nil, "OVERLAY")
            flash:SetTexture("Interface/Buttons/WHITE8x8")
            flash:SetBlendMode("ADD")
            flash:SetVertexColor(1.0, 0.10, 0.10, 0.0) -- start hidden
            flash:Hide()
            tick.MSUF_flash = flash

            local g = flash:CreateAnimationGroup()
            local a = g:CreateAnimation("Alpha")
            a:SetFromAlpha(1.0)
            a:SetToAlpha(0.0)
            a:SetDuration(MSUF_GetEmpowerStageBlinkTime())
            tick.MSUF_flashAnim = a
            g:SetScript("OnFinished", function()
                if flash then
                    flash:Hide()
                    flash:SetAlpha(0.0)
                end
            end)
            tick.MSUF_flashGroup = g
        end

        if tick.MSUF_flash then
            tick.MSUF_flash:SetHeight(h)
        end

        if tick.MSUF_glow then
            tick.MSUF_glow:SetHeight(h)
        end
    end

    for i = count + 1, #frame.empowerTicks do
        local t = frame.empowerTicks[i]
        if t then
            t:Hide()
            if t.MSUF_glow then t.MSUF_glow:Hide() end
            if t.MSUF_flash then t.MSUF_flash:Hide() end
        end
    end
end

local MSUF_EMPOWER_STAGE_COLORS = {
    {0.20, 0.90, 0.20, 0.18}, -- Stage 1 (green)
    {0.95, 0.80, 0.20, 0.18}, -- Stage 2 (yellow)
    {1.00, 0.55, 0.20, 0.18}, -- Stage 3 (orange)
    {1.00, 0.25, 0.25, 0.18}, -- Stage 4 (red)
}

local function MSUF_EnsureEmpowerStageSegments(frame, count)
    if not frame or not frame.statusBar then return end
    frame.empowerSegments = frame.empowerSegments or {}

    for i = 1, count do
        local seg = frame.empowerSegments[i]
        if not seg then
            seg = frame.statusBar:CreateTexture(nil, "ARTWORK")
            seg:SetColorTexture(1, 1, 1, 0.18)
            seg:SetBlendMode("ADD")
            frame.empowerSegments[i] = seg
        end
        seg:Show()
    end

    for i = count + 1, #frame.empowerSegments do
        frame.empowerSegments[i]:Hide()
    end
end


local _msufUnifiedDirectionCache = nil

-- Unified fill direction is a GLOBAL setting. We keep it cheap here:
-- 1) Prefer reading MSUF_DB directly (no EnsureDB spam in layout paths).
-- 2) Fall back to EnsureDB only once if we somehow run before DB exists.
local function MSUF_GetUnifiedDirection()
    local db = _G.MSUF_DB
    if db and db.general ~= nil then
        local v = (db.general.castbarUnifiedDirection and true or false)
        _msufUnifiedDirectionCache = v
        return v
    end

    -- If DB isn't ready yet, return cached value if we have one.
    if _msufUnifiedDirectionCache ~= nil then
        return _msufUnifiedDirectionCache
    end

    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
        db = _G.MSUF_DB
    end

    local v = (db and db.general and db.general.castbarUnifiedDirection) and true or false
    _msufUnifiedDirectionCache = v
    return v
end

local function MSUF_GetUnifiedFillEnabled(frame)
    local v = MSUF_GetUnifiedDirection()
    if frame then
        frame.MSUF_cachedUnifiedDirection = v
    end
    return v
end

local _msufEmpowerColorStagesCache = nil

-- Empower stage coloring is a GLOBAL setting. Keep it cheap (no EnsureDB spam).
local function MSUF_IsEmpowerColorStagesEnabled()
    local db = _G.MSUF_DB
    if db and db.general ~= nil then
        local v = not (db.general.empowerColorStages == false)
        _msufEmpowerColorStagesCache = v
        return v
    end

    if _msufEmpowerColorStagesCache ~= nil then
        return _msufEmpowerColorStagesCache
    end

    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
        db = _G.MSUF_DB
    end

    local v = not (db and db.general and db.general.empowerColorStages == false)
    _msufEmpowerColorStagesCache = v
    return v
end


local function MSUF_LayoutEmpowerStageSegments(frame)
    if not frame or not frame.isEmpower or not frame.statusBar then return end
    if not frame.empowerStageEnds or not frame.empowerTotalWithGrace then return end
    if not MSUF_IsEmpowerColorStagesEnabled() then
        if frame.empowerSegments then
            for i = 1, #frame.empowerSegments do
                local seg = frame.empowerSegments[i]
                if seg then seg:Hide() end
            end
        end
        return
    end

    local w = frame.statusBar:GetWidth() or 0
    if w <= 1 then
        frame.MSUF_empowerLayoutPending = true
        return
    end

    local total = frame.empowerTotalWithGrace
    local stageEnds = frame.empowerStageEnds
    local h = frame.statusBar:GetHeight() or 18
    local reverse = (frame.statusBar.GetReverseFill and frame.statusBar:GetReverseFill()) or false

    -- Tick positions must match the *visual* progression.
    -- When unified fill direction is OFF, empower uses "remaining" (total-elapsed), so stage markers need to be mirrored.
    local unified = MSUF_GetUnifiedFillEnabled(frame)
    local useRemaining = not unified
    local segCount = #stageEnds
    local lastEnd = stageEnds[#stageEnds] or 0
    local hasHold = (total and lastEnd and total > lastEnd + 0.001)
    if hasHold then
        segCount = segCount + 1
    end

    MSUF_EnsureEmpowerStageSegments(frame, segCount)

    local function setSeg(i, startT, endT, color)
        if not total or total <= 0 then return end
        local seg = frame.empowerSegments[i]
        if not seg then return end

        local startFrac = startT / total
        local endFrac = endT / total
        if startFrac < 0 then startFrac = 0 elseif startFrac > 1 then startFrac = 1 end
        if endFrac < 0 then endFrac = 0 elseif endFrac > 1 then endFrac = 1 end
        if endFrac < startFrac then endFrac = startFrac end

        local posStart = startFrac
        local posEnd = endFrac
        if useRemaining then
            -- Mirror the timeline so stage blocks align with a draining empower bar (remaining value).
            posStart = 1 - endFrac
            posEnd = 1 - startFrac
            if posStart < 0 then posStart = 0 elseif posStart > 1 then posStart = 1 end
            if posEnd < 0 then posEnd = 0 elseif posEnd > 1 then posEnd = 1 end
            if posEnd < posStart then posEnd = posStart end
        end

        local x0 = w * posStart
        local x1 = w * posEnd
        local segW = x1 - x0
        if segW < 0 then segW = 0 end

        local r,g,b,a = 1,1,1,0.18
        if color then r,g,b,a = color[1],color[2],color[3],color[4] end
        seg:SetColorTexture(r,g,b,a)
        seg:SetHeight(h)

        seg:ClearAllPoints()
        if reverse then
            seg:SetPoint("TOPRIGHT", frame.statusBar, "TOPRIGHT", -x0, 0)
            seg:SetPoint("BOTTOMRIGHT", frame.statusBar, "BOTTOMRIGHT", -x0, 0)
            seg:SetWidth(segW)
        else
            seg:SetPoint("TOPLEFT", frame.statusBar, "TOPLEFT", x0, 0)
            seg:SetPoint("BOTTOMLEFT", frame.statusBar, "BOTTOMLEFT", x0, 0)
            seg:SetWidth(segW)
        end
    end

    local prev = 0
    for i = 1, #stageEnds do
        local endT = stageEnds[i] or prev
        local col = MSUF_EMPOWER_STAGE_COLORS[i] or MSUF_EMPOWER_STAGE_COLORS[#MSUF_EMPOWER_STAGE_COLORS]
        setSeg(i, prev, endT, col)
        prev = endT
    end

    if hasHold then
        setSeg(#stageEnds + 1, prev, total, {1,1,1,0.10})
    end

    frame.MSUF_empowerLayoutPending = false
end

local function MSUF_BlinkEmpowerTick(frame, idx)
    if not frame or not frame.empowerTicks then return end
    local tick = frame.empowerTicks[idx]
    if not tick then return end

    local flash = tick.MSUF_flash
    local g = tick.MSUF_flashGroup

    local baseAlpha = tick.MSUF_baseAlpha or MSUF_EMPOWER_TICK_BASE_ALPHA or 0.85
    local baseW = tick.MSUF_baseWidth or 2
    tick.MSUF_baseWidth = baseW

    tick.MSUF_blinkToken = (tick.MSUF_blinkToken or 0) + 1
    local token = tick.MSUF_blinkToken

    if flash then
        flash:SetVertexColor(1.0, 0.10, 0.10, 1.0)
        flash:SetAlpha(1.0)
        flash:Show()
        if g then
            if tick.MSUF_flashAnim then
                tick.MSUF_flashAnim:SetDuration(MSUF_GetEmpowerStageBlinkTime())
            end
            g:Stop()
            g:Play()
        end
    end

    if tick.SetWidth then tick:SetWidth(MSUF_EMPOWER_TICK_FLASH_WIDTH or 4) end
    if tick.SetVertexColor then
        tick:SetVertexColor(1.0, 0.10, 0.10, 1.0)
    elseif tick.SetColorTexture then
        tick:SetColorTexture(1.0, 0.10, 0.10, 1.0)
    end

    if C_Timer and C_Timer.After then
        local _dur = MSUF_GetEmpowerStageBlinkTime()
        C_Timer.After(_dur, function()
            if not tick or token ~= tick.MSUF_blinkToken then return end
            if tick.SetWidth then tick:SetWidth(baseW) end
            if tick.SetVertexColor then
                tick:SetVertexColor(1.0, 1.0, 1.0, baseAlpha)
            elseif tick.SetColorTexture then
                tick:SetColorTexture(1.0, 1.0, 1.0, baseAlpha)
            elseif tick.SetAlpha then
                tick:SetAlpha(baseAlpha)
            end
        end)
    end
end

_G.MSUF_BlinkEmpowerTick = MSUF_BlinkEmpowerTick

local function MSUF_LayoutEmpowerTicks(frame)
    if not frame or not frame.isEmpower or not frame.statusBar then return end
    if not frame.empowerStageEnds or not frame.empowerTotalWithGrace then return end

    local w = frame.statusBar:GetWidth() or 0
    if w <= 1 then
        frame.MSUF_empowerLayoutPending = true
        return
    end

    local total = frame.empowerTotalWithGrace
    local stageEnds = frame.empowerStageEnds
    local reverse = (frame.statusBar.GetReverseFill and frame.statusBar:GetReverseFill()) or false

    -- Tick positions must match the *visual* progression.
    -- When unified fill direction is OFF, empower uses "remaining" (total-elapsed), so stage markers need to be mirrored.
    local unified = MSUF_GetUnifiedFillEnabled(frame)
    local useRemaining = not unified

    MSUF_LayoutEmpowerStageSegments(frame)

    MSUF_EnsureEmpowerTicks(frame, #stageEnds)

    for i = 1, #stageEnds do
        local tEnd = stageEnds[i]
        local frac = tEnd / total
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        local posFrac = frac
        local x = w * posFrac

        local tick = frame.empowerTicks[i]
        tick:ClearAllPoints()
        if reverse then
            tick:SetPoint("CENTER", frame.statusBar, "RIGHT", -x, 0)
        else
            tick:SetPoint("CENTER", frame.statusBar, "LEFT", x, 0)
        end

        local glow = tick.MSUF_glow
        if glow then
            glow:ClearAllPoints()
            glow:SetPoint("CENTER", tick, "CENTER", 0, 0)
            glow:SetWidth(MSUF_EMPOWER_TICK_GLOW_WIDTH or 12)
            glow:SetHeight(frame.statusBar:GetHeight() or 18)
        end

        local flash = tick.MSUF_flash
        if flash then
            flash:ClearAllPoints()
            flash:SetPoint("CENTER", tick, "CENTER", 0, 0)
            local fw = (MSUF_EMPOWER_TICK_FLASH_WIDTH or 4) * 3
            if fw < 10 then fw = 10 end
            flash:SetWidth(fw)
            flash:SetHeight(frame.statusBar:GetHeight() or 18)
        end
    end

    frame.MSUF_empowerLayoutPending = false
end

_G.MSUF_LayoutEmpowerTicks = MSUF_LayoutEmpowerTicks

local function MSUF_PlayerCastbar_EmpowerStart(self, spellID)
    if not self or not self.statusBar then
        return
    end

    self.isEmpower = true
    self.interruptFeedbackEndTime = nil
    if self.latencyBar then self.latencyBar:Hide() end

    local name, text, texture = UnitCastingInfo("player")
    if not name then
        name, text, texture = UnitChannelInfo("player")
    end
    if self.icon and texture then
        self.icon:SetTexture(texture)
    end
    if self.castText then
        MSUF_SetTextIfChanged(self.castText, name or "")
    end

    local tl = MSUF_BuildEmpowerTimeline("player")
    local now = ((GetTimePreciseSec and GetTimePreciseSec()) or GetTime())
    self.empowerStartTime     = tl.castStartSec or now
    self.empowerStageEnds     = tl.stageEnds
    self.empowerTotalBase     = tl.totalBase
    self.empowerTotalWithGrace= tl.totalWithGrace
    self.empowerNextStage     = 1
    local rf = MSUF_GetCastbarReverseFillForFrame(self, true)

    -- Apply empowered reverse-fill + timer direction via shared helper (guardrails-safe).
    if _G.MSUF_ApplyCastbarTimerDirection and type(UnitCastingDuration) == "function" then
        local okD, dObj
        if type(MSUF_FastCall) == "function" then
            okD, dObj = MSUF_FastCall(UnitCastingDuration, "player")
        else
            okD, dObj = true, UnitCastingDuration("player")
        end
        if okD and dObj then
            _G.MSUF_ApplyCastbarTimerDirection(self.statusBar, dObj, rf)
        else
            _G.MSUF_ApplyCastbarTimerDirection(self.statusBar, nil, rf)
        end
    elseif _G.MSUF_ApplyCastbarTimerDirection then
        _G.MSUF_ApplyCastbarTimerDirection(self.statusBar, nil, rf)
    else
        self.statusBar:SetReverseFill(rf)
    end

    self.statusBar:SetMinMaxValues(0, self.empowerTotalWithGrace)
    local elapsed0 = now - (self.empowerStartTime or now)
    if elapsed0 < 0 then elapsed0 = 0 end
    if elapsed0 > self.empowerTotalWithGrace then elapsed0 = self.empowerTotalWithGrace end
    self.statusBar:SetValue(elapsed0)

    self.MSUF_empowerLayoutPending = false
    MSUF_LayoutEmpowerTicks(self)

    if not self.MSUF_empowerSizeHooked and self.statusBar and self.statusBar.HookScript then
        self.MSUF_empowerSizeHooked = true
        self.statusBar:HookScript("OnSizeChanged", function()
            if self.isEmpower and self.MSUF_empowerLayoutPending then
                MSUF_LayoutEmpowerTicks(self)
            end
        end)
    end

    self:SetScript("OnUpdate", nil)
    MSUF_EnsureCastbarManager()
    if MSUF_RegisterCastbar then
        MSUF_RegisterCastbar(self)
    end
    if MSUF_UpdateCastbarFrame then
        MSUF_UpdateCastbarFrame(self, 0)
    end

    MSUF_PlayerCastbar_UpdateColorForInterruptible(self)
    self:Show()
end


-- Clear empower state + visuals (called on STOP/SUCCEEDED/FAILED/INTERRUPTED).
-- Keep it small and safe: we only hide our textures and unregister from the CastbarManager.
local function MSUF_PlayerCastbar_ClearEmpower(self, hideNow)
    if not self then return end

    self.isEmpower = nil
    self.empowerStartTime = nil
    self.empowerStageEnds = nil
    self.empowerTotalBase = nil
    self.empowerTotalWithGrace = nil
    self.empowerNextStage = nil

    -- Cached plain numbers (avoid stale data + secret-safe).
    self._msufEmpowerStartNum = nil
    self._msufEmpowerTotalNum = nil
    self._msufEmpowerBaseNum = nil
    self._msufEmpowerStageEndsNum = nil

    self.MSUF_empowerLayoutPending = false

    if self.empowerTicks then
        for i = 1, #self.empowerTicks do
            local t = self.empowerTicks[i]
            if t then
                if t.Hide then t:Hide() end
                if t.MSUF_glow and t.MSUF_glow.Hide then t.MSUF_glow:Hide() end
                if t.MSUF_flash and t.MSUF_flash.Hide then t.MSUF_flash:Hide() end
            end
        end
    end

    if self.empowerSegments then
        for i = 1, #self.empowerSegments do
            local seg = self.empowerSegments[i]
            if seg and seg.Hide then seg:Hide() end
        end
    end

    if hideNow then
        if self.SetScript then self:SetScript("OnUpdate", nil) end
        if MSUF_UnregisterCastbar then
            MSUF_UnregisterCastbar(self)
        end
        if self.timeText then
            MSUF_SetTextIfChanged(self.timeText, "")
        end
        if self.latencyBar and self.latencyBar.Hide then
            self.latencyBar:Hide()
        end
        if self.Hide then
            self:Hide()
        end
    end
end



-------------------------------------------------------------------------------
-- Player-only: Channeled Cast "Haste Markers" (5 white static lines)
-- Goal: Always visible from channel START (not progress-based), positions shift with current player spell haste.
-- Secret-safe: uses only UnitSpellHaste("player") + StatusBar width. No duration math, no combat log, no secret comparisons.
-------------------------------------------------------------------------------

-- Master toggle (Options → Castbars → Behavior → "Show channeled cast tick lines")
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



-- Unhalted-style non-empower player castbar (cast/channel): self-driven via OnUpdate and hard-stops when the cast/channel is gone.
local function MSUF_PlayerCastbar_UnhaltedUpdate(self, event)
    if not self or not self.unit or not self.statusBar then return end
    if self.isEmpower then return end

    local CAST_START = {
        UNIT_SPELLCAST_START = true,
        UNIT_SPELLCAST_INTERRUPTIBLE = true,
        UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
        UNIT_SPELLCAST_SENT = true,
    }
    local CAST_STOP = {
        UNIT_SPELLCAST_STOP = true,
        UNIT_SPELLCAST_CHANNEL_STOP = true,
    }
    local CHANNEL_START = {
        UNIT_SPELLCAST_CHANNEL_START = true,
    }

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

        local __msuf_rf = nil
if type(_G.MSUF_BuildCastState) == "function" then
    local st = _G.MSUF_BuildCastState(self.unit, self)
    __msuf_rf = st and st.reverseFill
end
if __msuf_rf == nil then
    __msuf_rf = (type(_G.MSUF_GetCastbarReverseFillForFrame) == "function" and _G.MSUF_GetCastbarReverseFillForFrame(self, false)) or false
end
__msuf_rf = (__msuf_rf == true)

if self.statusBar then
    if type(_G.MSUF_ApplyCastbarTimerDirection) == "function" then
        _G.MSUF_ApplyCastbarTimerDirection(self.statusBar, castDuration, __msuf_rf)
    elseif type(_G.MSUF_SetStatusBarTimerDuration) == "function" then
        _G.MSUF_SetStatusBarTimerDuration(self.statusBar, castDuration, __msuf_rf)
        if self.statusBar.SetReverseFill then
            MSUF_FastCall(self.statusBar.SetReverseFill, self.statusBar, (__msuf_rf and true or false))
        end
    elseif self.statusBar.SetTimerDuration then
        MSUF_FastCall(self.statusBar.SetTimerDuration, self.statusBar, castDuration, 0)
        if self.statusBar.SetReverseFill then
            MSUF_FastCall(self.statusBar.SetReverseFill, self.statusBar, (__msuf_rf and true or false))
        end
    elseif self.statusBar.SetReverseFill then
        MSUF_FastCall(self.statusBar.SetReverseFill, self.statusBar, (__msuf_rf and true or false))
    end
end


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

                self._msufChanNilSince = nil

        self:SetScript("OnUpdate", function()
            -- Hard stop: if no longer casting, kill the bar immediately (fixes lingering channels like Mind Flay).
            local u = self._msufActiveCastUnit or unit or self.unit or "player"
            local _castName, _, _, _, _, _, _, _ni = UnitCastingInfo(u)
            if not _castName then
                self:SetScript("OnUpdate", nil)
                self._msufActiveCastUnit = nil
                MSUF_PlayerChannelHasteMarkers_Hide(self)
                if self.latencyBar then self.latencyBar:Hide() end
                if self.timeText then MSUF_SetTextIfChanged(self.timeText, "") end
                if self.statusBar and self.statusBar.SetValue then MSUF_FastCall(self.statusBar.SetValue, self.statusBar, 0) end
                self:Hide()
                return
            end
	        local _newNI = false
	        if _ni then _newNI = true end
            if _newNI ~= self.isNotInterruptible then
                self.isNotInterruptible = _newNI
                MSUF_PlayerCastbar_UpdateColorForInterruptible(self)
            end

            local ok, remaining = MSUF_FastCall(castDuration.GetRemainingDuration, castDuration)

            -- "Glow effect": fade the fill color towards white as the cast approaches completion.
            if ok and type(_G.MSUF_ApplyCastbarGlowFade) == "function" then
                local okT, total = MSUF_FastCall(castDuration.GetTotalDuration, castDuration)
                if okT then
                    _G.MSUF_ApplyCastbarGlowFade(self, remaining, total)
                end
            end

            if self.timeText then
                local t = ""
                if ok then
                    local okFmt, s = MSUF_FastCall(string.format, "%.1f", remaining)
                    t = okFmt and s or (remaining ~= nil and tostring(remaining) or "")
                end
                MSUF_SetTextIfChanged(self.timeText, t)
            end
        end)

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

        local __msuf_rf = nil
if type(_G.MSUF_BuildCastState) == "function" then
    local st = _G.MSUF_BuildCastState(self.unit, self)
    __msuf_rf = st and st.reverseFill
end
if __msuf_rf == nil then
    __msuf_rf = (type(_G.MSUF_GetCastbarReverseFillForFrame) == "function" and _G.MSUF_GetCastbarReverseFillForFrame(self, true)) or false
end
__msuf_rf = (__msuf_rf == true)

if self.statusBar then
    if type(_G.MSUF_ApplyCastbarTimerDirection) == "function" then
        _G.MSUF_ApplyCastbarTimerDirection(self.statusBar, channelDuration, __msuf_rf)
    elseif type(_G.MSUF_SetStatusBarTimerDuration) == "function" then
        _G.MSUF_SetStatusBarTimerDuration(self.statusBar, channelDuration, __msuf_rf)
        if self.statusBar.SetReverseFill then
            MSUF_FastCall(self.statusBar.SetReverseFill, self.statusBar, (__msuf_rf and true or false))
        end
    elseif self.statusBar.SetTimerDuration then
        MSUF_FastCall(self.statusBar.SetTimerDuration, self.statusBar, channelDuration, 0)
        if self.statusBar.SetReverseFill then
            MSUF_FastCall(self.statusBar.SetReverseFill, self.statusBar, (__msuf_rf and true or false))
        end
    elseif self.statusBar.SetReverseFill then
        MSUF_FastCall(self.statusBar.SetReverseFill, self.statusBar, (__msuf_rf and true or false))
    end
end


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

        -- Unhalted-style channel drive: value always increases; direction is handled via reverseFill.
        if self.statusBar and self.statusBar.SetMinMaxValues and channelDuration.GetTotalDuration then
            local okTotal, total = MSUF_FastCall(channelDuration.GetTotalDuration, channelDuration)
            if okTotal then
                MSUF_FastCall(self.statusBar.SetMinMaxValues, self.statusBar, 0, total)
                self.MSUF_channelTotal = total
            end
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

        self:SetScript("OnUpdate", function()
            -- Hard stop (graceful): UnitChannelInfo can briefly return nil during back-to-back channel refresh/queue windows.
            -- Keep a tiny persistence window to avoid "blink / micro re-channel" while still killing truly-ended lingering channels.
            local now = (type(GetTime) == "function") and GetTime() or 0
            local u = self._msufActiveCastUnit or unit or self.unit or "player"
            local _chanName, _, _, _, _, _, _ni = UnitChannelInfo(u)

            if not _chanName then
                local since = self._msufChanNilSince
                if not since then
                    self._msufChanNilSince = now
                    return
                end

                -- Default grace bridges refresh gaps; on some builds the gap can be as large as SpellQueueWindow.
                local grace = self._msufChanNilGrace
                if type(grace) ~= "number" then
                    local qms = 0
                    if GetCVar then qms = tonumber(GetCVar("SpellQueueWindow") or "0") or 0 end
                    if qms < 0 then qms = 0 end
                    grace = (qms / 1000) + 0.12
                    if grace < 0.20 then grace = 0.20 end
                end
                if grace < 0.05 then grace = 0.05 end
                if grace > 0.80 then grace = 0.80 end

                if (now - since) < grace then
                    return
                end

                self._msufChanNilSince = nil
                self:SetScript("OnUpdate", nil)
                self._msufActiveCastUnit = nil
                MSUF_PlayerChannelHasteMarkers_Hide(self)
                if self.latencyBar then self.latencyBar:Hide() end
                if self.timeText then MSUF_SetTextIfChanged(self.timeText, "") end
                if self.statusBar and self.statusBar.SetValue then MSUF_FastCall(self.statusBar.SetValue, self.statusBar, 0) end
                self:Hide()
                return
            end

            -- Channel is active again; clear any pending nil-grace tracking.
            self._msufChanNilSince = nil

            -- Update haste markers during the channel (throttled). Visible from start; repositions if haste changes.
            if (now - (self._msufPlayerChannelHasteMarkersLastT or 0)) > 0.15 then
                self._msufPlayerChannelHasteMarkersLastT = now
                MSUF_PlayerChannelHasteMarkers_Update(self, false)
            end

            local _newNI = false
            if _ni then _newNI = true end
            if _newNI ~= self.isNotInterruptible then
                self.isNotInterruptible = _newNI
                MSUF_PlayerCastbar_UpdateColorForInterruptible(self)
            end

            local ok, remaining = MSUF_FastCall(channelDuration.GetRemainingDuration, channelDuration)
            if ok then
                -- "Glow effect": fade the fill color towards white as the channel approaches completion.
                if type(_G.MSUF_ApplyCastbarGlowFade) == "function" then
                    local total = self.MSUF_channelTotal
                    if total == nil then
                        local okT, t = MSUF_FastCall(channelDuration.GetTotalDuration, channelDuration)
                        if okT then total = t end
                    end
                    if total ~= nil then
                        _G.MSUF_ApplyCastbarGlowFade(self, remaining, total)
                    end
                end

                if self.statusBar and self.statusBar.SetValue then
                    local v = remaining
                    if self.MSUF_channelTotal and type(self.MSUF_channelTotal) == 'number' then
                        v = self.MSUF_channelTotal - remaining
                        if v < 0 then v = 0 end
                    end
                    MSUF_FastCall(self.statusBar.SetValue, self.statusBar, v)
                end
                if self.timeText then
                    local okFmt, s = MSUF_FastCall(string.format, "%.1f", remaining)
                    MSUF_SetTextIfChanged(self.timeText, okFmt and s or (remaining ~= nil and tostring(remaining) or ""))
                end
            end
        end)

        self:Show()
        return
    end

    if CAST_STOP[event] then
        self:SetScript("OnUpdate", nil)
        self._msufChanNilSince = nil
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

function MSUF_InitSafePlayerCastbar()
    if not MSUF_PlayerCastbar then
        local frame = CreateFrame("Frame", "MSUF_PlayerCastBar", UIParent)
        frame:SetClampedToScreen(true)
        MSUF_PlayerCastbar = frame
        frame.unit = "player"

        local height = 18
        frame:SetSize(200, height) -- Breite wird in Reanchor gesetzt

        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(frame)
        background:SetColorTexture(0, 0, 0, 1)
        frame.background = background

        local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        icon:SetSize(height, height)
        icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.icon = icon

        local statusBar = CreateFrame("StatusBar", nil, frame)
        statusBar:SetPoint("LEFT", icon, "RIGHT", 0, 0)
        statusBar:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        -- Pixel-perfect: avoid internal -2 height padding (causes a visible 1px line when outline thickness is 0)
    statusBar:SetPoint("TOP", frame, "TOP", 0, 0)
    statusBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)

        local texture = MSUF_GetCastbarTexture()
        statusBar:SetStatusBarTexture(texture)
        statusBar:GetStatusBarTexture():SetHorizTile(true)
        frame.statusBar = statusBar

        local backgroundBar = frame:CreateTexture(nil, "ARTWORK")
        backgroundBar:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
        backgroundBar:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        local bgTex = texture
        if type(_G.MSUF_GetCastbarBackgroundTexture) == "function" then
            local t = _G.MSUF_GetCastbarBackgroundTexture()
            if t and t ~= "" then
                bgTex = t
            end
        end
        backgroundBar:SetTexture(bgTex)
        backgroundBar:SetVertexColor(0.176, 0.176, 0.176, 1)
        frame.backgroundBar = backgroundBar

        local castText = statusBar:CreateFontString(nil, "OVERLAY")
        local fontPath, fontSize, fontFlags = GameFontHighlight:GetFont()
        castText:SetFont(fontPath, fontSize, fontFlags)
        castText:SetPoint("LEFT", statusBar, "LEFT", 2, 0)
        frame.castText = castText

        EnsureDB()
        local g = MSUF_DB.general
        local timeX = g.castbarPlayerTimeOffsetX or -2
        local timeY = g.castbarPlayerTimeOffsetY or 0

        local timeText = statusBar:CreateFontString(nil, "OVERLAY")
        local latencyBar = statusBar:CreateTexture(nil, "OVERLAY")
        latencyBar:SetColorTexture(1, 0, 0, 0.25) -- rot, halbtransparent
        latencyBar:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
        latencyBar:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        latencyBar:SetWidth(0)
        latencyBar:Hide()
        frame.latencyBar = latencyBar

        if not frame.MSUF_latencyHooked and frame.HookScript then
            frame:HookScript("OnSizeChanged", function(f)
                if f and f.latencyBar and f.MSUF_latencyLastDurSec and f.MSUF_latencyLastDurSec > 0 then
                    MSUF_PlayerCastbar_UpdateLatencyZone(f, f.MSUF_latencyLastIsChanneled, f.MSUF_latencyLastDurSec)
                end
            end)
            frame.MSUF_latencyHooked = true
        end
        timeText:SetFont(fontPath, fontSize, fontFlags)
        timeText:SetPoint("RIGHT", statusBar, "RIGHT", timeX, timeY)
        timeText:SetJustifyH("RIGHT")
        timeText:SetText("")
        frame.timeText = timeText

    if _G.MSUF_ApplyCastbarOutline then _G.MSUF_ApplyCastbarOutline(frame, true) end
        frame.empowerStageTicks = frame.empowerStageTicks or {}
        local numStages = 5      -- oder 4, je nach Taste; wir machen es erst mal generisch
        local barHeight = height -- height ist oben in der Funktion definiert

        for i = 1, numStages - 1 do
            local tick = frame.empowerStageTicks[i]
            if not tick then
                tick = statusBar:CreateTexture(nil, "OVERLAY")
                tick:SetColorTexture(1, 1, 1, 0.8) -- dünne helle Linie
                frame.empowerStageTicks[i] = tick
            end

            tick:SetSize(3, barHeight)  -- 2 px breit, volle Höhe
            tick:Hide()                 -- Standard: versteckt, nur bei Empower sichtbar
        end

        frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP",  "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")

                frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player", "vehicle")

        frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player", "vehicle")

        frame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "vehicle")

        frame:RegisterEvent("PLAYER_ENTERING_WORLD")

        frame:SetScript("OnEvent", MSUF_PlayerCastbar_OnEvent)
        frame:Hide()
    end
        C_Timer.After(0, function()
            if not MSUF_PlayerCastbar or not MSUF_PlayerCastbar_Cast then return end
            local castName = UnitCastingInfo("player")
            local chanName = UnitChannelInfo("player")
            if not (castName or chanName) and type(UnitHasVehicleUI) == "function" and UnitHasVehicleUI("player") and type(UnitExists) == "function" and UnitExists("vehicle") then
                castName = UnitCastingInfo("vehicle")
                chanName = UnitChannelInfo("vehicle")
            end
            if castName or chanName then
                MSUF_PlayerCastbar_Cast(MSUF_PlayerCastbar)
            end
        end)
end


-- ============================================================
-- Performance: dirty-only layout helpers (SetPoint/Size/Alpha)
-- ============================================================
function MSUF_AttachBlizzardTargetFrame()
    if not TargetFrame then
        return
    end

    local msufTarget = UnitFrames and UnitFrames["target"]
    if not msufTarget then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    local g = MSUF_DB and MSUF_DB.general
    local offsetX = g and g.castbarTargetOffsetX or 65
    local offsetY = g and g.castbarTargetOffsetY or -15

    -- Dirty-only: don't ClearAllPoints/SetPoint unless it actually changed.
    MSUF_SetPointIfChanged(TargetFrame, "CENTER", msufTarget, "CENTER", offsetX, offsetY)
end

function MSUF_ReanchorTargetCastBar()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}
    local frame = MSUF_TargetCastbar or _G["TargetCastBar"]
    if not frame then return end

    if g.enableTargetCastbar == false then
        frame:SetScript("OnUpdate", nil)
        if frame.timeText and MSUF_IsCastTimeEnabled(frame) then
            MSUF_SetTextIfChanged(frame.timeText, "")
        end
        if frame.latencyBar then
            frame.latencyBar:Hide()
        end
        frame:Hide()
        if MSUF_TargetCastbarPreview then
            MSUF_TargetCastbarPreview:Hide()
        end
        return
    end

    local msufTarget = UnitFrames and UnitFrames["target"]
    local offsetX = g.castbarTargetOffsetX or 65
    local offsetY = g.castbarTargetOffsetY or -15

    -- Anchor: either attach to unitframe or detach to UIParent
    if g.castbarTargetDetached then
        MSUF_SetPointIfChanged(frame, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        if not msufTarget then return end
        MSUF_SetPointIfChanged(frame, "BOTTOMLEFT", msufTarget, "TOPLEFT", offsetX, offsetY)
    end

    local width = g.castbarTargetBarWidth
    if not width or width <= 0 then
        if (not g.castbarTargetDetached) and msufTarget and msufTarget.GetWidth then
            width = msufTarget:GetWidth()
        end
    end
    if not width or width <= 0 then
        width = frame.GetWidth and frame:GetWidth() or 240
    end
    if width and width > 0 then
        local snap = _G.MSUF_Snap
        if type(snap) == "function" then
            width = snap(frame, width)
        end
        local height = frame:GetHeight() or 18
        MSUF_SetWidthIfChanged(frame, width)

        if frame.statusBar then
            MSUF_SetWidthIfChanged(frame.statusBar, width - height - 1)
        end
    end

    if frame.timeText then
        local showTime = (g.showTargetCastTime ~= false)
        frame.timeText:Show()
        MSUF_SetAlphaIfChanged(frame.timeText, showTime and 1 or 0)
        if not showTime then
            MSUF_SetTextIfChanged(frame.timeText, "")
        end
    end

    if frame.timeText and frame.statusBar then
        local x = g.castbarTargetTimeOffsetX
        if x == nil then x = g.castbarPlayerTimeOffsetX or -2 end
        local y = g.castbarTargetTimeOffsetY
        if y == nil then y = g.castbarPlayerTimeOffsetY or 0 end

        MSUF_SetPointIfChanged(frame.timeText, "RIGHT", frame.statusBar, "RIGHT", x, y)
        MSUF_SetJustifyHIfChanged(frame.timeText, "RIGHT")
    end

    if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
        pcall(_G.MSUF_ApplyCastbarTimeTextLayout, frame, "target")
    end

    if MSUF_TargetCastbarPreview and MSUF_PositionTargetCastbarPreview then
        MSUF_PositionTargetCastbarPreview()
    end
end
function MSUF_ReanchorFocusCastBar()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}
    local frame = MSUF_FocusCastbar or _G["FocusCastBar"]
    if not frame then return end

    if g.enableFocusCastbar == false then
        frame:SetScript("OnUpdate", nil)
        if frame.timeText and MSUF_IsCastTimeEnabled(frame) then
            MSUF_SetTextIfChanged(frame.timeText, "")
        end
        if frame.latencyBar then
            frame.latencyBar:Hide()
        end
        frame:Hide()
        if MSUF_FocusCastbarPreview then
            MSUF_FocusCastbarPreview:Hide()
        end
        return
    end

    local msufFocus = UnitFrames and UnitFrames["focus"]

    local offsetX = g.castbarFocusOffsetX or (g.castbarTargetOffsetX or 65)
    local offsetY = g.castbarFocusOffsetY or (g.castbarTargetOffsetY or -15)

    -- Anchor: either attach to unitframe or detach to UIParent
    if g.castbarFocusDetached then
        MSUF_SetPointIfChanged(frame, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        if not msufFocus then return end
        MSUF_SetPointIfChanged(frame, "BOTTOMLEFT", msufFocus, "TOPLEFT", offsetX, offsetY)
    end

    local width = g.castbarFocusBarWidth
    if not width or width <= 0 then
        if (not g.castbarFocusDetached) and msufFocus and msufFocus.GetWidth then
            width = msufFocus:GetWidth()
        end
    end
    if not width or width <= 0 then
        width = frame.GetWidth and frame:GetWidth() or 240
    end
    if width and width > 0 then
        local snap = _G.MSUF_Snap
        if type(snap) == "function" then
            width = snap(frame, width)
        end
        local height = frame:GetHeight() or 18
        MSUF_SetWidthIfChanged(frame, width)

        if frame.statusBar then
            MSUF_SetWidthIfChanged(frame.statusBar, width - height - 1)
        end
    end

    if frame.timeText and frame.statusBar then
        local enabledTime = MSUF_IsCastTimeEnabled(frame)
        frame.timeText:Show()
        MSUF_SetAlphaIfChanged(frame.timeText, enabledTime and 1 or 0)
        if not enabledTime then
            MSUF_SetTextIfChanged(frame.timeText, "")
        end

        local tx = g.castbarFocusTimeOffsetX or (g.castbarPlayerTimeOffsetX or -2)
        local ty = g.castbarFocusTimeOffsetY or (g.castbarPlayerTimeOffsetY or 0)
        MSUF_SetPointIfChanged(frame.timeText, "RIGHT", frame.statusBar, "RIGHT", tx, ty)
        MSUF_SetJustifyHIfChanged(frame.timeText, "RIGHT")
    end

    if MSUF_FocusCastbarPreview and MSUF_FocusCastbarPreview.timeText and MSUF_FocusCastbarPreview.statusBar then
        local enabledTime = MSUF_IsCastTimeEnabled(frame)
        MSUF_FocusCastbarPreview.timeText:Show()
        MSUF_SetAlphaIfChanged(MSUF_FocusCastbarPreview.timeText, enabledTime and 1 or 0)
        if not enabledTime then
            MSUF_FocusCastbarPreview.timeText:SetText("")
        end

        local tx = g.castbarFocusTimeOffsetX or (g.castbarPlayerTimeOffsetX or -2)
        local ty = g.castbarFocusTimeOffsetY or (g.castbarPlayerTimeOffsetY or 0)
        MSUF_SetPointIfChanged(MSUF_FocusCastbarPreview.timeText, "RIGHT", MSUF_FocusCastbarPreview.statusBar, "RIGHT", tx, ty)
        MSUF_SetJustifyHIfChanged(MSUF_FocusCastbarPreview.timeText, "RIGHT")
    end

    if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
        pcall(_G.MSUF_ApplyCastbarTimeTextLayout, frame, "focus")
    end

    if MSUF_FocusCastbarPreview and MSUF_PositionFocusCastbarPreview then
        MSUF_PositionFocusCastbarPreview()
    end
end

local function MSUF_HideBlizzardPlayerCastbar()
    EnsureDB()
    local frames = {}

    if PlayerCastingBarFrame then
        table.insert(frames, PlayerCastingBarFrame)
    end

    if CastingBarFrame and CastingBarFrame ~= PlayerCastingBarFrame then
        table.insert(frames, CastingBarFrame)
    end

    if #frames == 0 then
        return
    end

    for _, frame in ipairs(frames) do
        if frame and not frame.MSUF_HideHooked then
            frame.MSUF_HideHooked = true

            hooksecurefunc(frame, "Show", function(self)
                -- As long as MSUF is running, never allow the Blizzard player castbar(s) to show.
                -- This is intentionally NOT tied to MSUF_DB.general.enablePlayerCastbar.
                -- If the user disables the MSUF player castbar, they should not silently fall back
                -- to Blizzard (which can cause edge-case "0 interaction" popups).
                self:Hide()
            end)
        end

        -- Always hide while MSUF is loaded.
        frame:Hide()
    end
end

function _G.MSUF_SetPlayerCastbarTestMode(active, keepSetting)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local want
    -- keepSetting=true means: do not persist and do not consult the stored setting.
    -- We use this for the "auto test cast while popup is open" behaviour.
    if keepSetting then
        want = active and true or false
    else
        g.playerCastbarTestMode = active and true or false
        want = g.playerCastbarTestMode and true or false
    end

    if not MSUF_UnitEditModeActive then
        want = false
    end

    if type(MSUF_InitSafePlayerCastbar) == "function" then
        MSUF_InitSafePlayerCastbar()
    end

    -- In MSUF Edit Mode the user drags/edits the *preview* castbar.
    -- For best UX, run the dummy-cast animation on the preview (if available)
    -- so you can see changes live where you're editing.
    local fReal = _G.MSUF_PlayerCastbar
    local fPrev = _G.MSUF_PlayerCastbarPreview
    local usePreview = (want and MSUF_UnitEditModeActive and g.castbarPlayerPreviewEnabled and fPrev and fPrev.statusBar)

    local function StopTest(frame, isPreview)
        if not frame or not frame.MSUF_testMode then
            return
        end
        frame.MSUF_testMode = nil
        frame.MSUF_testStart = nil
        frame.MSUF_testDuration = nil
        if frame.statusBar then
            frame.statusBar._msufTestMinMax = nil
            if isPreview then
                frame.statusBar:SetMinMaxValues(0, 1)
                frame.statusBar:SetValue(0.5)
            end
        end
        frame:SetScript("OnUpdate", nil)

        -- Reset optional visual effects when leaving dummy-cast mode.
        if type(_G.MSUF_ResetCastbarGlowFade) == "function" then
            pcall(_G.MSUF_ResetCastbarGlowFade, frame)
        end
        if frame.latencyBar and frame.latencyBar.Hide then
            frame.latencyBar:Hide()
        end

        if isPreview then
            if frame.castText then
                MSUF_SetTextIfChanged(frame.castText, "Player castbar preview")
            end
            if frame.timeText then
                MSUF_SetTextIfChanged(frame.timeText, "")
                if frame.MSUF_testCreatedTimeText and frame.timeText.Hide then
                    frame.timeText:Hide()
                end
            end
            frame.MSUF_testCreatedTimeText = nil

            if g.castbarPlayerPreviewEnabled then
                frame:Show()
            else
                frame:Hide()
            end
        else
            -- Let normal castbar logic take over; hide if no real cast is active.
            local hasCast = UnitCastingInfo("player") or UnitChannelInfo("player")
            if not hasCast and type(UnitHasVehicleUI) == "function" and UnitHasVehicleUI("player") and type(UnitExists) == "function" and UnitExists("vehicle") then
                hasCast = UnitCastingInfo("vehicle") or UnitChannelInfo("vehicle")
            end
            if not hasCast then
                if frame.timeText then
                    MSUF_SetTextIfChanged(frame.timeText, "")
                end
                frame:Hide()
            end
        end
    end

    -- IMPORTANT: when disabling, stop BOTH preview + real bars.
    -- Otherwise the preview can keep casting if we pick the real bar as "f".
    if not want then
        StopTest(fPrev, true)
        StopTest(fReal, false)
        return
    end

    -- If we're switching to preview, ensure the real bar isn't left in test mode (and vice versa).
    if usePreview then
        StopTest(fReal, false)
    else
        StopTest(fPrev, true)
    end

    local f = usePreview and fPrev or fReal
    if not f or not f.statusBar then
        return
    end

    -- If we're animating the preview, keep the real bar hidden (unless a real cast is happening).
    if usePreview and fReal and fReal ~= fPrev then
        -- Don't fight the normal castbar driver: only hide if no real cast is active.
        local hasCast = UnitCastingInfo("player") or UnitChannelInfo("player")
        if not hasCast and type(UnitHasVehicleUI) == "function" and UnitHasVehicleUI("player") and type(UnitExists) == "function" and UnitExists("vehicle") then
            hasCast = UnitCastingInfo("vehicle") or UnitChannelInfo("vehicle")
        end
        if not hasCast then
            fReal:SetScript("OnUpdate", nil)
            if fReal.timeText then
                MSUF_SetTextIfChanged(fReal.timeText, "")
            end
            fReal:Hide()
        end
    end

    -- Ensure the preview has a timeText so the dummy cast shows duration.
    -- (We mark it so we can hide it again when test mode is disabled.)
    if usePreview and (not f.timeText) and f.statusBar and f.statusBar.CreateFontString then
        local fontPath, fontSize, flags = GameFontHighlight:GetFont()
        local tt = f.statusBar:CreateFontString(nil, "OVERLAY")
        tt:SetFont(fontPath, fontSize, flags)
        tt:SetJustifyH("RIGHT")
        tt:SetPoint("RIGHT", f.statusBar, "RIGHT", -2, 0)
        tt:SetText("")
        f.timeText = tt
        f.MSUF_testCreatedTimeText = true
    end

    -- (disable path handled above)

    -- Enable runtime test mode (dummy casting loop).
    f.MSUF_testMode = true
    if f.hideTimer and f.hideTimer.Cancel then
        f.hideTimer:Cancel()
    end
    f.hideTimer = nil
    f.interruptFeedbackEndTime = nil

    if f.castText then
        MSUF_SetTextIfChanged(f.castText, "Test Cast")
    end
    if f.icon then
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    local dur = 4.0
    f.MSUF_testStart = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
    f.MSUF_testDuration = dur

    -- Respect the per-unit cast time toggle while still running the dummy cast.
    local showTime = (g and g.showPlayerCastTime ~= false)
    if f.timeText then
        if f.timeText.SetShown then
            f.timeText:SetShown(showTime)
        else
            if showTime and f.timeText.Show then
                f.timeText:Show()
            end
            if (not showTime) and f.timeText.Hide then
                f.timeText:Hide()
            end
        end
        if not showTime then
            MSUF_SetTextIfChanged(f.timeText, "")
        end
    end

    if f.statusBar then
        f.statusBar._msufTestMinMax = nil
    end

    f:Show()

    -- Apply current visual settings/anchors so edits update live.
    if type(MSUF_ReanchorPlayerCastBar) == "function" then
        MSUF_ReanchorPlayerCastBar()
    end
    if type(MSUF_UpdateCastbarVisuals) == "function" then
        MSUF_UpdateCastbarVisuals()
    end

    f:SetScript("OnUpdate", function(self, elapsed)
        if not self.MSUF_testMode or not self.statusBar then
            return
        end
        local now = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
        local d = self.MSUF_testDuration or 4.0
        if d <= 0 then d = 4.0 end
        local t = now - (self.MSUF_testStart or now)
        if t < 0 then t = 0 end
        local p = t % d
        if not self.statusBar._msufTestMinMax then
            self.statusBar:SetMinMaxValues(0, d)
            self.statusBar._msufTestMinMax = true
        end
        self.statusBar:SetValue(p)

        -- Respect the user's "Show cast time" toggle while in test mode.
        local showTime = (g and g.showPlayerCastTime ~= false)
        if self.timeText then
            if self.timeText.SetShown then
                self.timeText:SetShown(showTime)
            elseif not showTime and self.timeText.Hide then
                self.timeText:Hide()
            elseif showTime and self.timeText.Show then
                self.timeText:Show()
            end
            local remain = d - p
            if remain < 0 then remain = 0 end
            if showTime then
                MSUF_SetTextIfChanged(self.timeText, string.format("%.1f", remain))
            else
                MSUF_SetTextIfChanged(self.timeText, "")
            end
        end

        -- Edit Mode visuals: latency indicator + glow effect (if enabled in options)
        if self.latencyBar then
            MSUF_PlayerCastbar_UpdateLatencyZone(self, false, d)
        end
        if type(_G.MSUF_ApplyCastbarGlowFade) == "function" then
            _G.MSUF_ApplyCastbarGlowFade(self, d - p, d)
        end
    end)
end

-- Target castbar: looping dummy cast on the TARGET castbar preview while the target castbar popup is open.
-- We do NOT override bar colors here; MSUF_UpdateCastbarVisuals applies the user's configured colors.
function _G.MSUF_SetTargetCastbarTestMode(active, keepSetting)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local want
    if keepSetting then
        want = active and true or false
    else
        g.targetCastbarTestMode = active and true or false
        want = g.targetCastbarTestMode and true or false
    end

    -- Only while MSUF Edit Mode is active.
    if not MSUF_UnitEditModeActive then
        want = false
    end

    local fPrev = _G.MSUF_TargetCastbarPreview
    local f = (fPrev and fPrev.statusBar) and fPrev or nil
    if not f or not f.statusBar then
        return
    end

    -- Ensure time text exists on the preview.
    if not f.timeText and f.statusBar and f.statusBar.CreateFontString then
        f.timeText = f.statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.timeText:SetPoint("RIGHT", f.statusBar, "RIGHT", -4, 0)
        f.timeText:SetJustifyH("RIGHT")
    end

    if not want then
        if f.MSUF_targetTestMode then
            f.MSUF_targetTestMode = nil
            f:SetScript("OnUpdate", nil)
            if f.statusBar and f.statusBar.SetMinMaxValues then
                f.statusBar:SetMinMaxValues(0, 1)
                f.statusBar:SetValue(0.5)
            end
            if f.castText and f.castText.SetText then
                f.castText:SetText("Target castbar preview")
            end
            if f.timeText and f.timeText.SetText then
                f.timeText:SetText("")
            end
	            if type(_G.MSUF_ResetCastbarGlowFade) == "function" then
	                _G.MSUF_ResetCastbarGlowFade(f)
	            end
        end
        return
    end

    -- Start/refresh the dummy cast.
    f.MSUF_targetTestMode = true

    if MSUF_ReanchorTargetCastBar then
        MSUF_ReanchorTargetCastBar()
    end
    if MSUF_UpdateCastbarVisuals then
        MSUF_UpdateCastbarVisuals()
    end

    if f.castText and f.castText.SetText then
        f.castText:SetText("Test Cast")
        f.castText:Show()
        f.castText:SetAlpha(1)
    end

    if f.icon and f.icon.SetTexture then
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if f.icon.Show then f.icon:Show() end
    end

    local showTime = (g.showTargetCastTime ~= false)
    if f.timeText then
        if showTime then
            f.timeText:Show()
            f.timeText:SetAlpha(1)
        else
            f.timeText:SetText("")
            f.timeText:Show()
            f.timeText:SetAlpha(0)
        end
    end

    local duration = 4.0
    f.MSUF_testStart = GetTime()
    f.MSUF_testDur = duration
    if f.statusBar and f.statusBar.SetMinMaxValues then
        f.statusBar:SetMinMaxValues(0, duration)
    end

    f:SetScript("OnUpdate", function(self)
        if not self or not self.MSUF_targetTestMode then
            return
        end

        local now = GetTime()
        local elapsed = now - (self.MSUF_testStart or now)
        local dur = self.MSUF_testDur or 4.0
        if dur <= 0 then dur = 4.0 end

        local phase = elapsed % dur
        local remaining = dur - phase

        if self.statusBar and self.statusBar.SetValue then
            self.statusBar:SetValue(phase)
        end

        if self.timeText and self.timeText.SetText then
            if (g.showTargetCastTime ~= false) then
                self.timeText:SetText(string.format("%.1f", remaining))
                self.timeText:SetAlpha(1)
            else
                self.timeText:SetText("")
                self.timeText:SetAlpha(0)
            end
        end

	        if type(_G.MSUF_ApplyCastbarGlowFade) == "function" then
	            _G.MSUF_ApplyCastbarGlowFade(self, remaining, dur)
	        end
    end)
end

-- Focus castbar: looping dummy cast on the FOCUS castbar preview while the focus castbar popup is open.
-- We do NOT override bar colors here; MSUF_UpdateCastbarVisuals applies the user's configured colors.
function _G.MSUF_SetFocusCastbarTestMode(active, keepSetting)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local want
    if keepSetting then
        want = active and true or false
    else
        g.focusCastbarTestMode = active and true or false
        want = g.focusCastbarTestMode and true or false
    end

    -- Only while MSUF Edit Mode is active.
    if not MSUF_UnitEditModeActive then
        want = false
    end

    local fPrev = _G.MSUF_FocusCastbarPreview
    local f = (fPrev and fPrev.statusBar) and fPrev or nil
    if not f or not f.statusBar then
        return
    end

    -- Ensure time text exists on the preview.
    if not f.timeText and f.statusBar and f.statusBar.CreateFontString then
        f.timeText = f.statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.timeText:SetPoint("RIGHT", f.statusBar, "RIGHT", -4, 0)
        f.timeText:SetJustifyH("RIGHT")
    end

    if not want then
        if f.MSUF_focusTestMode then
            f.MSUF_focusTestMode = nil
            f:SetScript("OnUpdate", nil)
            if f.statusBar and f.statusBar.SetMinMaxValues then
                f.statusBar:SetMinMaxValues(0, 1)
                f.statusBar:SetValue(0.5)
            end
            if f.castText and f.castText.SetText then
                f.castText:SetText("Focus castbar preview")
            end
            if f.timeText and f.timeText.SetText then
                f.timeText:SetText("")
            end
	            if type(_G.MSUF_ResetCastbarGlowFade) == "function" then
	                _G.MSUF_ResetCastbarGlowFade(f)
	            end
        end
        return
    end

    -- Start/refresh the dummy cast.
    f.MSUF_focusTestMode = true

    if MSUF_ReanchorFocusCastBar then
        MSUF_ReanchorFocusCastBar()
    end
    if MSUF_UpdateCastbarVisuals then
        MSUF_UpdateCastbarVisuals()
    end

    if f.castText and f.castText.SetText then
        f.castText:SetText("Test Cast")
        f.castText:Show()
        f.castText:SetAlpha(1)
    end

    if f.icon and f.icon.SetTexture then
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if f.icon.Show then f.icon:Show() end
    end

    local showTime = (g.showFocusCastTime ~= false)
    if f.timeText then
        if showTime then
            f.timeText:Show()
            f.timeText:SetAlpha(1)
        else
            f.timeText:SetText("")
            f.timeText:Show()
            f.timeText:SetAlpha(0)
        end
    end

    local duration = 4.0
    f.MSUF_testStart = GetTime()
    f.MSUF_testDur = duration
    if f.statusBar and f.statusBar.SetMinMaxValues then
        f.statusBar:SetMinMaxValues(0, duration)
    end

    f:SetScript("OnUpdate", function(self)
        if not self or not self.MSUF_focusTestMode then
            return
        end

        local now = GetTime()
        local elapsed = now - (self.MSUF_testStart or now)
        local dur = self.MSUF_testDur or 4.0
        if dur <= 0 then dur = 4.0 end

        local phase = elapsed % dur
        local remaining = dur - phase

        if self.statusBar and self.statusBar.SetValue then
            self.statusBar:SetValue(phase)
        end

	        if self.timeText and self.timeText.SetText then
            if (g.showFocusCastTime ~= false) then
                self.timeText:SetText(string.format("%.1f", remaining))
                self.timeText:SetAlpha(1)
            else
                self.timeText:SetText("")
                self.timeText:SetAlpha(0)
            end
        end

	        if type(_G.MSUF_ApplyCastbarGlowFade) == "function" then
	            _G.MSUF_ApplyCastbarGlowFade(self, remaining, dur)
	        end
    end)
end

-- Boss castbar: looping dummy cast on the BOSS castbar preview while the boss castbar popup is open.
-- We do NOT override bar colors here; MSUF_UpdateBossCastbarPreview applies the user's configured colors.
function _G.MSUF_SetBossCastbarTestMode(active, keepSetting)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local want
    if keepSetting then
        want = active and true or false
    else
        g.bossCastbarTestMode = active and true or false
        want = g.bossCastbarTestMode and true or false
    end

    -- Only while MSUF Edit Mode is active.
    if not MSUF_UnitEditModeActive then
        want = false
    end

    -- Make sure previews exist/are positioned before we try to drive a dummy cast.
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end

    local function IterateBossPreviews(fn)
        local f1 = _G.MSUF_BossCastbarPreview
        if f1 then fn(f1) end

        local n = tonumber(_G.MAX_BOSS_FRAMES) or 5
        if n < 1 or n > 12 then n = 5 end
        for i = 2, n do
            local f = _G["MSUF_BossCastbarPreview" .. i]
            if f then fn(f) end
        end
    end

    local found = false
    IterateBossPreviews(function(f)
        if f and f.statusBar then found = true end
    end)
    if not found then
        return
    end

    if not want then
        IterateBossPreviews(function(f)
            if not f or not f.statusBar then return end
            if f.MSUF_bossTestMode then
                f.MSUF_bossTestMode = nil
                f:SetScript("OnUpdate", nil)

                if f.statusBar.SetMinMaxValues then
                    f.statusBar:SetMinMaxValues(0, 1)
                    f.statusBar:SetValue(0.5)
                end

                -- Restore the boss preview's default (no-fill) look when leaving test mode.
                if f.statusBar.GetStatusBarTexture then
                    local tex = f.statusBar:GetStatusBarTexture()
                    if tex and tex.SetAlpha then
                        tex:SetAlpha(0)
                    end
                    f.statusBar.MSUF_hideFillTexture = true
                end

                if f.castText and f.castText.SetText then
                    f.castText:SetText("Boss castbar preview")
                end
                if f.timeText and f.timeText.SetText then
                    f.timeText:SetText("")
                end
	            if type(_G.MSUF_ResetCastbarGlowFade) == "function" then
	                _G.MSUF_ResetCastbarGlowFade(f)
	            end
            end
        end)
        return
    end

    -- Start/refresh the dummy cast for ALL boss previews.
    local duration = 4.0
    local startTime = GetTime()

    IterateBossPreviews(function(f)
        if not f or not f.statusBar then return end

        -- Ensure time text exists on the preview.
        if not f.timeText and f.statusBar and f.statusBar.CreateFontString then
            f.timeText = f.statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            f.timeText:SetPoint("RIGHT", f.statusBar, "RIGHT", -4, 0)
            f.timeText:SetJustifyH("RIGHT")
        end

        f.MSUF_bossTestMode = true
        f.MSUF_testStart = startTime
        f.MSUF_testDur = duration

        -- Boss preview edit-mode setup hides the fill texture by default.
        -- For the dummy test cast we want a visible filling bar.
        if f.statusBar.GetStatusBarTexture then
            local tex = f.statusBar:GetStatusBarTexture()
            if tex and tex.SetAlpha then
                tex:SetAlpha(1)
            end
            f.statusBar.MSUF_hideFillTexture = nil
        end

        if f.castText and f.castText.SetText then
            f.castText:SetText("Test Cast")
        end

        -- IMPORTANT: Do NOT force-show the icon in test mode.
        -- Icon visibility must be controlled by the normal preview layout (Show Icon toggle).
        -- We only ensure a stable, non-secret texture is present when the icon is shown.
        if f.icon and f.icon.SetTexture then
            f.icon:SetTexture("Interface\Icons\INV_Misc_QuestionMark")
        end

        local showTime = (g.showBossCastTime ~= false)
        if f.timeText then
            if showTime then
                if f.timeText.Show then f.timeText:Show() end
                f.timeText:SetAlpha(1)
            else
                f.timeText:SetText("")
                if f.timeText.Show then f.timeText:Show() end
                f.timeText:SetAlpha(0)
            end
        end

        if f.statusBar.SetMinMaxValues then
            f.statusBar:SetMinMaxValues(0, duration)
        end

        f:SetScript("OnUpdate", function(self)
            if not self or not self.MSUF_bossTestMode then
                return
            end

            local now = GetTime()
            local elapsed = now - (self.MSUF_testStart or now)
            local dur = self.MSUF_testDur or 4.0
            if dur <= 0 then dur = 4.0 end

            local phase = elapsed % dur
            local remaining = dur - phase

            -- Keep the fill texture visible while the dummy cast runs (boss preview hides it by default).
            if self.statusBar and self.statusBar.GetStatusBarTexture then
                local t = self.statusBar:GetStatusBarTexture()
                if t and t.SetAlpha then
                    local a = 1
                    if t.GetAlpha then
                        a = t:GetAlpha() or 0
                    end
                    if a < 0.9 then
                        t:SetAlpha(1)
                    end
                end
            end

            if self.statusBar and self.statusBar.SetValue then
                self.statusBar:SetValue(phase)
            end

            -- Keep label stable even if other refreshes happen while editing.
            if self.castText and self.castText.GetText and self.castText.SetText then
                if self.castText:GetText() ~= "Test Cast" then
                    self.castText:SetText("Test Cast")
                end
            end

            if self.timeText and self.timeText.SetText then
                if (g.showBossCastTime ~= false) then
                    self.timeText:SetText(string.format("%.1f", remaining))
                    self.timeText:SetAlpha(1)
                else
                    self.timeText:SetText("")
                    self.timeText:SetAlpha(0)
                end
            end

	            if type(_G.MSUF_ApplyCastbarGlowFade) == "function" then
	                _G.MSUF_ApplyCastbarGlowFade(self, remaining, dur)
	            end
        end)
    end)
end

-- ============================================================
-- Player castbar icon layout helper (prevents "reserved black gap")
-- Detach only when IconOffsetX ~= 0 (Y is cosmetic)
-- NOTE: Player castbar icon is positionable via Edit Mode, but visibility respects the player Icon toggle
--       (except while in Edit Mode, where we keep it visible so it can be repositioned).
-- ============================================================
function _G.MSUF_ApplyPlayerCastbarIconLayout(bar, g, topInset, bottomInset)
    if not bar or not g then return end
    local statusBar = bar.statusBar
    if not statusBar then return end

    topInset = tonumber(topInset) or 0
    bottomInset = tonumber(bottomInset) or 0

    local height = bar.GetHeight and (bar:GetHeight() or 18) or 18

    -- Global + per-player override (BUT: player icon is Edit-Mode driven; force visible if icon exists)
    local showIconLocal = (g.castbarShowIcon ~= false)
    if g.castbarPlayerShowIcon ~= nil then
        showIconLocal = (g.castbarPlayerShowIcon ~= false)
    end

    -- Player castbar icon toggle should work during normal gameplay.
    -- While in MSUF/Blizzard Edit Mode, keep the icon visible so it can still be positioned.
    local isPlayerBar = (bar == _G.MSUF_PlayerCastbar or bar == _G.MSUF_PlayerCastbarPreview or bar == _G.PlayerCastingBarFrame or bar == _G.CastingBarFrame)
    if isPlayerBar then
        local inMSUFEdit = (_G.MSUF_UnitEditModeActive == true)
        local inBlizzEdit = (EditModeManagerFrame and EditModeManagerFrame.IsShown and EditModeManagerFrame:IsShown())
        if inMSUFEdit or inBlizzEdit then
            showIconLocal = true
        end
    end

    local iconOXLocal = tonumber(g.castbarPlayerIconOffsetX)
    if iconOXLocal == nil then iconOXLocal = tonumber(g.castbarIconOffsetX) or 0 end

    local iconOYLocal = tonumber(g.castbarPlayerIconOffsetY)
    if iconOYLocal == nil then iconOYLocal = tonumber(g.castbarIconOffsetY) or 0 end

    local iconSizeLocal = tonumber(g.castbarPlayerIconSize)
    if not iconSizeLocal or iconSizeLocal <= 0 then
        iconSizeLocal = tonumber(g.castbarIconSize) or 0
        if not iconSizeLocal or iconSizeLocal <= 0 then
            iconSizeLocal = height
        end
    end
    if iconSizeLocal < 6 then iconSizeLocal = 6 end
    if iconSizeLocal > 128 then iconSizeLocal = 128 end

    -- IMPORTANT: detach only on X
    local iconDetached = (iconOXLocal ~= 0)

    local icon = bar.Icon or bar.icon or (bar.IconFrame and bar.IconFrame.Icon)

    if icon then
        if showIconLocal then
            icon:Show()

            local k = (iconDetached and "D" or "A") .. ":" .. tostring(iconSizeLocal) .. ":" .. tostring(iconOXLocal) .. ":" .. tostring(iconOYLocal)
            if icon._msufPCIconKey ~= k then
                icon:SetSize(iconSizeLocal, iconSizeLocal)
                icon:ClearAllPoints()

                -- IMPORTANT: Parent the icon to statusBar so it renders above the bar texture,
                -- but anchor it to the *bar* to avoid anchor dependency loops.
                icon:SetParent(statusBar)
                icon:SetPoint("LEFT", bar, "LEFT", iconOXLocal, iconOYLocal)

                -- Render: above bar texture, below castbar texts.
                if icon.SetDrawLayer then
                    icon:SetDrawLayer("ARTWORK", 5)
                end

                icon._msufPCIconKey = k
            end
        else
            icon:Hide()
        end
    end

    -- Layout key (only re-anchor when state changes)
    local layoutKey = (showIconLocal and icon and (not iconDetached)) and ("G:" .. tostring(iconSizeLocal)) or "F"
    if statusBar._msufPCLayoutKey ~= layoutKey then
        statusBar:ClearAllPoints()

        if showIconLocal and icon and not iconDetached then
            statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", iconSizeLocal + 1, topInset)
            statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, bottomInset)
        else
            statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, topInset)
            statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, bottomInset)
        end

        statusBar._msufPCLayoutKey = layoutKey
    end
end

-- ============================================================
-- Player castbar sizing: always follow castbar size keys (NOT unitframe width).
-- Also keep the player preview frame in perfect sync with the real bar.
-- ============================================================
local function MSUF_GetPlayerCastbarDesiredSize(g, fallbackW, fallbackH)
    local w = g and tonumber(g.castbarPlayerBarWidth) or nil
    local h = g and tonumber(g.castbarPlayerBarHeight) or nil

    if not w or w <= 0 then
        w = g and tonumber(g.castbarGlobalWidth) or nil
    end
    if not h or h <= 0 then
        h = g and tonumber(g.castbarGlobalHeight) or nil
    end

    if not w or w <= 0 then w = fallbackW or 250 end
    if not h or h <= 0 then h = fallbackH or 18 end

    return w, h
end

local function MSUF_ApplyPlayerCastbarSizeAndLayout(bar, g, w, h)
    if not bar then return end

    local snap = _G.MSUF_Snap
    if type(snap) == "function" then
        if w ~= nil then w = snap(bar, w) end
        if h ~= nil then h = snap(bar, h) end
    end

    -- Size
    if MSUF_SetWidthIfChanged then
        MSUF_SetWidthIfChanged(bar, w)
    else
        bar:SetWidth(w)
    end
    if MSUF_SetHeightIfChanged then
        MSUF_SetHeightIfChanged(bar, h)
    else
        bar:SetHeight(h)
    end

    -- Icon/statusbar layout (player uses a special layout helper)
    if bar.statusBar and type(_G.MSUF_ApplyPlayerCastbarIconLayout) == "function" then
        _G.MSUF_ApplyPlayerCastbarIconLayout(bar, g, -1, 1)
    end

    -- Empower stage tick heights must follow bar height
    if bar.empowerStageTicks then
        local bh = bar:GetHeight() or h
        for _, tick in pairs(bar.empowerStageTicks) do
            if tick and tick.SetHeight then
                tick:SetHeight(bh)
            end
        end
    end
end

function MSUF_ReanchorPlayerCastBar()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}

    -- Always hide Blizzard player castbar; we no longer use it as a fallback.
    MSUF_HideBlizzardPlayerCastbar()

    if g.enablePlayerCastbar == false then
        if MSUF_PlayerCastbar then
            MSUF_PlayerCastbar:SetScript("OnUpdate", nil)
            MSUF_PlayerCastbar.interruptFeedbackEndTime = nil
            if MSUF_PlayerCastbar.timeText then
                MSUF_PlayerCastbar.timeText:SetText("")
            end
            if MSUF_PlayerCastbar.latencyBar then
                MSUF_PlayerCastbar.latencyBar:Hide()
            end
            MSUF_PlayerCastbar:Hide()
        end
        if MSUF_PlayerCastbarPreview then
            MSUF_PlayerCastbarPreview:Hide()
        end
        return
    end

    MSUF_InitSafePlayerCastbar()

    local msufPlayer = UnitFrames and UnitFrames["player"]
    if not MSUF_PlayerCastbar then
        return
    end
    if (not g.castbarPlayerDetached) and (not msufPlayer) then
        return
    end

    local offsetX = g.castbarPlayerOffsetX or 0
    local offsetY = g.castbarPlayerOffsetY or 5

    -- Dirty-only anchor
    if MSUF_SetPointIfChanged then
        if g.castbarPlayerDetached then
        MSUF_SetPointIfChanged(MSUF_PlayerCastbar, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        MSUF_SetPointIfChanged(MSUF_PlayerCastbar, "BOTTOM", msufPlayer, "TOP", offsetX, offsetY)
    end
    else
        MSUF_PlayerCastbar:ClearAllPoints()
        if g.castbarPlayerDetached then
            MSUF_PlayerCastbar:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        else
            MSUF_PlayerCastbar:SetPoint("BOTTOM", msufPlayer, "TOP", offsetX, offsetY)
        end
    end

    local w, h = MSUF_GetPlayerCastbarDesiredSize(g, 250, 18)
    MSUF_ApplyPlayerCastbarSizeAndLayout(MSUF_PlayerCastbar, g, w, h)

    -- Cast-time text offsets + visibility
    if MSUF_PlayerCastbar.timeText and MSUF_PlayerCastbar.statusBar then
        local timeX = g.castbarPlayerTimeOffsetX or -2
        local timeY = g.castbarPlayerTimeOffsetY or 0

        if MSUF_SetPointIfChanged then
            MSUF_SetPointIfChanged(MSUF_PlayerCastbar.timeText, "RIGHT", MSUF_PlayerCastbar.statusBar, "RIGHT", timeX, timeY)
        else
            MSUF_PlayerCastbar.timeText:ClearAllPoints()
            MSUF_PlayerCastbar.timeText:SetPoint("RIGHT", MSUF_PlayerCastbar.statusBar, "RIGHT", timeX, timeY)
        end

        if MSUF_SetJustifyHIfChanged then
            MSUF_SetJustifyHIfChanged(MSUF_PlayerCastbar.timeText, "RIGHT")
        else
            MSUF_PlayerCastbar.timeText:SetJustifyH("RIGHT")
        end

        local showTime = (g.showPlayerCastTime ~= false)
        MSUF_PlayerCastbar.timeText:Show()
        if MSUF_SetAlphaIfChanged then
            MSUF_SetAlphaIfChanged(MSUF_PlayerCastbar.timeText, showTime and 1 or 0)
        else
            MSUF_PlayerCastbar.timeText:SetAlpha(showTime and 1 or 0)
        end
        if not showTime then
            MSUF_PlayerCastbar.timeText:SetText("")
        end
    end

    if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
        pcall(_G.MSUF_ApplyCastbarTimeTextLayout, MSUF_PlayerCastbar, "player")
    end

    -- Keep the PLAYER preview size 1:1 with the real bar (show/hide handled elsewhere)
    if MSUF_PlayerCastbarPreview then
        MSUF_ApplyPlayerCastbarSizeAndLayout(MSUF_PlayerCastbarPreview, g, w, h)
    end

    if MSUF_PlayerCastbarPreview and MSUF_PositionPlayerCastbarPreview then
        MSUF_PositionPlayerCastbarPreview()
    end
end

MSUF_PlayerCastbarManageHooked = true -- Blizzard fallback removed; nothing to manage here.

local function MSUF_SyncBossCastbarSliders()
    EnsureDB()
    local g = MSUF_DB.general or {}
    local sx = _G["MSUF_CastbarBossXOffsetSlider"]
    local sy = _G["MSUF_CastbarBossYOffsetSlider"]
    local sw = _G["MSUF_CastbarBossWidthSlider"]
    local sh = _G["MSUF_CastbarBossHeightSlider"]

    if sx then MSUF_SetSliderValueSilent(sx, MSUF_ClampToSlider(sx, tonumber(g.bossCastbarOffsetX) or 0)) end
    if sy then MSUF_SetSliderValueSilent(sy, MSUF_ClampToSlider(sy, tonumber(g.bossCastbarOffsetY) or 0)) end
    if sw then MSUF_SetSliderValueSilent(sw, MSUF_ClampToSlider(sw, tonumber(g.bossCastbarWidth)  or 240)) end
    if sh then MSUF_SetSliderValueSilent(sh, MSUF_ClampToSlider(sh, tonumber(g.bossCastbarHeight) or 18)) end
end

MSUF_PlayerCastbarPreview  = MSUF_PlayerCastbarPreview  or nil
MSUF_TargetCastbarPreview  = MSUF_TargetCastbarPreview  or nil
MSUF_FocusCastbarPreview   = MSUF_FocusCastbarPreview   or nil

local function MSUF_CreateCastbarEditArrows(frame, unit)
    if not frame or frame.MSUF_CastbarArrowsCreated then
        return
    end
    frame.MSUF_CastbarArrowsCreated = true

    local arrowSize = 18

    local function Nudge(moveDX, moveDY, sizeDW, sizeDH)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general

        local offXKey, offYKey, barWKey, barHKey
        if unit == "player" then
            offXKey, offYKey = "castbarPlayerOffsetX", "castbarPlayerOffsetY"
            barWKey, barHKey = "castbarPlayerBarWidth", "castbarPlayerBarHeight"
        elseif unit == "target" then
            offXKey, offYKey = "castbarTargetOffsetX", "castbarTargetOffsetY"
            barWKey, barHKey = "castbarTargetBarWidth", "castbarTargetBarHeight"
        elseif unit == "focus" then
            offXKey, offYKey = "castbarFocusOffsetX", "castbarFocusOffsetY"
            barWKey, barHKey = "castbarFocusBarWidth", "castbarFocusBarHeight"
        elseif unit == "boss" then
            offXKey, offYKey = "bossCastbarOffsetX", "bossCastbarOffsetY"
            barWKey, barHKey = "bossCastbarWidth", "bossCastbarHeight"
        else
            return
        end

        if MSUF_EditModeSizing then
            local baseW = g[barWKey] or g.castbarGlobalWidth  or frame:GetWidth()  or 250
            local baseH = g[barHKey] or g.castbarGlobalHeight or frame:GetHeight() or 18

            baseW = math.max(50, baseW + (sizeDW or 0))
            baseH = math.max(8,  baseH + (sizeDH or 0))

            g[barWKey] = math.floor(baseW + 0.5)
            g[barHKey] = math.floor(baseH + 0.5)

            if unit == "boss" then
            if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
                _G.MSUF_ApplyBossCastbarPositionSetting()
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                _G.MSUF_UpdateBossCastbarPreview()
            end
                MSUF_SyncBossCastbarSliders()
            if MSUF_SyncCastbarPositionPopup then
                MSUF_SyncCastbarPositionPopup("boss")
            end
            else
                if MSUF_UpdateCastbarVisuals then
                    MSUF_UpdateCastbarVisuals()
                end
            end
        else
            local defaultX, defaultY
            if unit == "player" then
                defaultX, defaultY = 0, 5
            elseif unit == "boss" then
                defaultX, defaultY = 0, 0
            else
                defaultX, defaultY = 65, -15
            end

            g[offXKey] = (g[offXKey] or defaultX) + (moveDX or 0)
            g[offYKey] = (g[offYKey] or defaultY) + (moveDY or 0)

            if unit == "player" and MSUF_ReanchorPlayerCastBar then
                MSUF_ReanchorPlayerCastBar()
            elseif unit == "target" and MSUF_ReanchorTargetCastBar then
                MSUF_ReanchorTargetCastBar()
            elseif unit == "focus" and MSUF_ReanchorFocusCastBar then
                MSUF_ReanchorFocusCastBar()
            elseif unit == "boss" then
            if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
                _G.MSUF_ApplyBossCastbarPositionSetting()
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                _G.MSUF_UpdateBossCastbarPreview()
            end
                MSUF_SyncBossCastbarSliders()
            end
        end

        if MSUF_UpdateCastbarEditInfo then
            MSUF_UpdateCastbarEditInfo(unit)
        end
        if MSUF_SyncCastbarPositionPopup then
            MSUF_SyncCastbarPositionPopup(unit)
        end


        if type(_G.MSUF_SetPlayerCastbarTestMode) == "function" then
            local popup = _G.MSUF_CastbarPositionPopup
            local want = (unit == "player") and popup and popup.IsShown and popup:IsShown() and popup.unit == "player"
            _G.MSUF_SetPlayerCastbarTestMode(want, true)
        end
        if type(_G.MSUF_SetTargetCastbarTestMode) == "function" then
            local popup = _G.MSUF_CastbarPositionPopup
            local want = (unit == "target") and popup and popup.IsShown and popup:IsShown() and popup.unit == "target"
            _G.MSUF_SetTargetCastbarTestMode(want, true)
        end
        if type(_G.MSUF_SetFocusCastbarTestMode) == "function" then
            local popup = _G.MSUF_CastbarPositionPopup
            local want = (unit == "focus") and popup and popup.IsShown and popup:IsShown() and popup.unit == "focus"
            _G.MSUF_SetFocusCastbarTestMode(want, true)
        end
    end

    local function CreateArrowButton(name, direction, point, relPoint, ofsX, ofsY, onClick, tooltipText)
        local btn = CreateFrame("Button", name, frame)
        btn:SetSize(arrowSize, arrowSize)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        btn._bg = bg

        local symbols = {
            LEFT  = "<",
            RIGHT = ">",
            UP    = "^",
            DOWN  = "v",
        }

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetText(symbols[direction] or "")
        label:SetTextColor(0, 0, 0, 1)
        btn._label = label

        btn:SetPoint(point, frame, relPoint or point, ofsX, ofsY)

        btn:SetScript("OnEnter", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
            if tooltipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)
            end
        end)

        btn:SetScript("OnLeave", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
            GameTooltip:Hide()
        end)

        btn:SetScript("OnMouseDown", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)

        btn:SetScript("OnMouseUp", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)

        if onClick then
            btn:SetScript("OnClick", onClick)
        end

        return btn
    end

    frame.MSUF_CastbarArrowUp = CreateArrowButton(
        frame:GetName() .. "ArrowUp",
        "UP",
        "BOTTOM", "TOP",
        0, 2,
        function()
            if MSUF_EditModeSizing then
                Nudge(0, 0, 0, -1)  -- height smaller
            else
                Nudge(0, 1, 0, 0)   -- move up
            end
        end,
        "Position: move up\nSize mode: decrease height"
    )

    frame.MSUF_CastbarArrowDown = CreateArrowButton(
        frame:GetName() .. "ArrowDown",
        "DOWN",
        "TOP", "BOTTOM",
        0, -2,
        function()
            if MSUF_EditModeSizing then
                Nudge(0, 0, 0, 1)   -- height bigger
            else
                Nudge(0, -1, 0, 0)  -- move down
            end
        end,
        "Position: move down\nSize mode: increase height"
    )

    frame.MSUF_CastbarArrowLeft = CreateArrowButton(
        frame:GetName() .. "ArrowLeft",
        "LEFT",
        "RIGHT", "LEFT",
        -2, 0,
        function()
            if MSUF_EditModeSizing then
                Nudge(0, 0, -1, 0)  -- width smaller
            else
                Nudge(-1, 0, 0, 0)  -- move left
            end
        end,
        "Position: move left\nSize mode: decrease width"
    )

    frame.MSUF_CastbarArrowRight = CreateArrowButton(
        frame:GetName() .. "ArrowRight",
        "RIGHT",
        "LEFT", "RIGHT",
        2, 0,
        function()
            if MSUF_EditModeSizing then
                Nudge(0, 0, 1, 0)   -- width bigger
            else
                Nudge(1, 0, 0, 0)   -- move right
            end
        end,
        "Position: move right\nSize mode: increase width"
    )
end

local function MSUF_CreateCastbarPreviewFrame(kind, frameName, opts)
    if type(_G.MSUF_CreateCastbarPreviewFrame) == "function" then
        return _G.MSUF_CreateCastbarPreviewFrame(kind, frameName, opts)
    end
    if MSUF_DevPrint then MSUF_DevPrint("MSUF: MSUF_CreateCastbarPreviewFrame missing") end
end

local function MSUF_SetupCastbarPreviewEditHandlers(frame, kind)
    local fn = _G.MSUF_SetupCastbarPreviewEditHandlers
    if type(fn) == "function" then
        return fn(frame, kind)
    end
end


function MSUF_ReanchorBossCastBar()
    if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
        _G.MSUF_ApplyBossCastbarPositionSetting()
    end
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end
    if type(MSUF_SyncBossCastbarSliders) == "function" then
        MSUF_SyncBossCastbarSliders()
    end
    if type(MSUF_SyncCastbarPositionPopup) == "function" then
        MSUF_SyncCastbarPositionPopup("boss")
    end
end

local function MSUF_CreatePlayerCastbarPreview()
    local fn = _G.MSUF_CreatePlayerCastbarPreview
    if type(fn) == "function" then
        return fn()
    end
    if MSUF_DevPrint then
        MSUF_DevPrint("MSUF: MSUF_CreatePlayerCastbarPreview missing")
    end
end


local function MSUF_CreateTargetCastbarPreview()
    local fn = _G.MSUF_CreateTargetCastbarPreview
    if type(fn) == "function" then
        return fn()
    end
    if MSUF_DevPrint then
        MSUF_DevPrint("MSUF: MSUF_CreateTargetCastbarPreview missing")
    end
end

local function MSUF_CreateFocusCastbarPreview()
    local fn = _G.MSUF_CreateFocusCastbarPreview
    if type(fn) == "function" then
        return fn()
    end
    if MSUF_DevPrint then
        MSUF_DevPrint("MSUF: MSUF_CreateFocusCastbarPreview missing")
    end
end


if type(_G.MSUF_UpdateBossCastbarPreview) ~= "function" then

    local function MSUF_CreateBossCastbarPreview_Fallback()
        if _G.MSUF_BossCastbarPreview then
            return _G.MSUF_BossCastbarPreview
        end

            local f = MSUF_CreateCastbarPreviewFrame("boss", "MSUF_BossCastbarPreview", {
        parent = UIParent,
        template = "BackdropTemplate",
        width = 240,
        height = 12,
        statusBarHeight = 12,
        initialValue = 0,
        hideFillTexture = true,
        showIcon = true,
        iconSize = 12,
        iconTexture = 134400, -- question mark
        showTime = true,
        timeLabel = "3.2",
    })
    f:EnableMouse(false)

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0, 0, 0, 0.55)
        f:SetBackdropBorderColor(0, 0, 0, 1)
    end

    f._msufIsPreview = true
    _G.MSUF_BossCastbarPreview = f
    return f
end

    local function MSUF_ApplyBossCastbarPreviewLayout_Fallback()
        local f = _G.MSUF_BossCastbarPreview
        if not f then return end

        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}

        local forcedW = tonumber(g.bossCastbarWidth)
        local forcedH = tonumber(g.bossCastbarHeight)

        local uf = _G["MSUF_boss1"]
        local w = (forcedW and forcedW > 10) and forcedW or (uf and uf.GetWidth and uf:GetWidth()) or 240
        local h = (forcedH and forcedH > 4) and forcedH or 12

        f:SetSize(w, h)

        local showIcon     = (g.castbarShowIcon ~= false)
        local iconOffsetX  = tonumber(g.castbarIconOffsetX) or 0
        local iconOffsetY  = tonumber(g.castbarIconOffsetY) or 0
        local iconDetached = (iconOffsetX ~= 0 or iconOffsetY ~= 0)

        if f.icon then
            f.icon:ClearAllPoints()
            f.icon:SetSize(h, h)
            f.icon:SetPoint("LEFT", f, "LEFT", iconOffsetX, iconOffsetY)
            f.icon:SetShown(showIcon)
        end

        if f.statusBar then
            f.statusBar:ClearAllPoints()

            if showIcon and f.icon and not iconDetached then
                f.statusBar:SetPoint("LEFT", f, "LEFT", h + 1, 0)
            else
                f.statusBar:SetPoint("LEFT", f, "LEFT", 1, 0)
            end

            f.statusBar:SetPoint("TOP", f, "TOP", 0, -1)
            f.statusBar:SetPoint("BOTTOM", f, "BOTTOM", 0, 1)
            f.statusBar:SetPoint("RIGHT", f, "RIGHT", -1, 0)

            if type(MSUF_GetCastbarTexture) == "function" and f.statusBar.SetStatusBarTexture then
                local ok, tex = MSUF_FastCall(MSUF_GetCastbarTexture)
                if ok and tex then
                    MSUF_FastCall(f.statusBar.SetStatusBarTexture, f.statusBar, tex)
                end
            end
        end

                local textOX = tonumber(g.bossCastTextOffsetX) or tonumber(g.bossCastbarTextOffsetX) or 0
        local textOY = tonumber(g.bossCastTextOffsetY) or tonumber(g.bossCastbarTextOffsetY) or 0

        -- Spell name show + boss-only font size override (fallback-safe)
        local showBossName = (g.showBossCastName ~= false)

        local baseSize = g.fontSize or 14
        local globalOverride = tonumber(g.castbarSpellNameFontSize) or 0
        local globalSize = (globalOverride and globalOverride > 0) and globalOverride or baseSize
        local bossSize = tonumber(g.bossCastSpellNameFontSize)
        if not bossSize or bossSize < 6 or bossSize > 72 then
            bossSize = globalSize
        else
            bossSize = math.floor(bossSize + 0.5)
        end

        if f.castText and f.timeText and f.statusBar then
            local tx = tonumber(g.bossCastTimeOffsetX)
            local ty = tonumber(g.bossCastTimeOffsetY)
            if tx == nil then tx = -2 end
            if ty == nil then ty = 0 end

            local showTime = (g.showBossCastTime ~= false)

            if type(_G.MSUF_ApplyBossCastbarTextsLayout) == "function" then
                _G.MSUF_ApplyBossCastbarTextsLayout(f, {
                    baselineTimeX = -2,
                    baselineTimeY = 0,
                    textOffsetX   = textOX,
                    textOffsetY   = textOY,
                    timeOffsetX   = tx,
                    timeOffsetY   = ty,
                    showName      = showBossName,
                    showTime      = showTime,
                    nameFontSize  = bossSize,
                })
            else
                -- Fallback (legacy)
                f.castText:ClearAllPoints()
                f.timeText:ClearAllPoints()

                f.castText:SetPoint("LEFT", f.statusBar, "LEFT", 2 + textOX, 0 + textOY)
                f.timeText:SetPoint("RIGHT", f.statusBar, "RIGHT", tx, ty)
                f.castText:SetPoint("RIGHT", f.timeText, "LEFT", -6, 0)

                f.castText:Show()
                f.castText:SetAlpha(showBossName and 1 or 0)
                if not showBossName then
                    f.castText:SetText("")
                end

                local font, _, flags = f.castText:GetFont()
                if font then
                    f.castText:SetFont(font, bossSize, flags)
                end

                f.timeText:Show()
                f.timeText:SetAlpha(showTime and 1 or 0)
            end
        end

    end

    local function MSUF_PositionBossCastbarPreview_Fallback()
        local f = _G.MSUF_BossCastbarPreview
        if not f then return end

        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local ox = tonumber(g.bossCastbarOffsetX) or 0
        local oy = tonumber(g.bossCastbarOffsetY) or 0

        if f.GetParent and f:GetParent() ~= UIParent then
            f:SetParent(UIParent)
        end

        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -320 + ox, -200 + oy)
    end

    function _G.MSUF_UpdateBossCastbarPreview()
        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}

        if not g.castbarPlayerPreviewEnabled or g.enableBossCastbar == false then
            if _G.MSUF_BossCastbarPreview then
                _G.MSUF_BossCastbarPreview:Hide()
            end
            return
        end

        local f = _G.MSUF_BossCastbarPreview or MSUF_CreateBossCastbarPreview_Fallback()
        MSUF_PositionBossCastbarPreview_Fallback()
        MSUF_ApplyBossCastbarPreviewLayout_Fallback()
        f:Show()
    end
end

local function MSUF_SetupBossCastbarPreviewEditMode()
    -- Prevent recursion:
    -- MSUF_UpdateBossCastbarPreview() is hooksecured below to call this setup function.
    -- If previews are disabled (or preview doesn't exist yet) we must NOT call Update from inside
    -- the hook chain, otherwise we can spiral into MSUF_Update -> hook -> Setup -> Update ...
    if _G.MSUF_BossPreviewSetupInProgress then return end

    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    if not g.castbarPlayerPreviewEnabled or g.enableBossCastbar == false then
        return
    end

    local function IterateBossPreviews(fn)
        local f1 = _G.MSUF_BossCastbarPreview
        if f1 then fn(f1) end

        local n = tonumber(_G.MAX_BOSS_FRAMES) or 5
        if n < 1 or n > 12 then n = 5 end
        for i = 2, n do
            local p = _G["MSUF_BossCastbarPreview" .. i]
            if p then fn(p) end
        end
    end

    local f = _G.MSUF_BossCastbarPreview
    if not f and type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        local prev = _G.MSUF_BossPreviewSetupInProgress
        _G.MSUF_BossPreviewSetupInProgress = true
        _G.MSUF_UpdateBossCastbarPreview()
        _G.MSUF_BossPreviewSetupInProgress = prev
        f = _G.MSUF_BossCastbarPreview
    end

    -- Apply the "no-fill" preview setup to ALL boss previews (boss1..bossN).
    IterateBossPreviews(function(p)
        if not p or not p.statusBar then return end
        if p.statusBar.GetStatusBarTexture then
            local t = p.statusBar:GetStatusBarTexture()
            if t and t.SetAlpha then
                t:SetAlpha(0)
            end
            if p.statusBar.SetValue then
                p.statusBar:SetValue(0)
            end
            p.statusBar.MSUF_hideFillTexture = true
        end
    end)

    -- Only boss1 needs edit handlers (settings are shared for all boss castbars).
    if f then
        MSUF_SetupCastbarPreviewEditHandlers(f, "boss")
    end
end

_G.MSUF_SetupBossCastbarPreviewEditMode = MSUF_SetupBossCastbarPreviewEditMode

if not _G.MSUF_BossPreviewSetupHooked then
    _G.MSUF_BossPreviewSetupHooked = true
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" and type(hooksecurefunc) == "function" then
        hooksecurefunc("MSUF_UpdateBossCastbarPreview", function()
            if _G.MSUF_BossPreviewSetupInProgress then return end
            EnsureDB()
            local g = (MSUF_DB and MSUF_DB.general) or {}
            if not g.castbarPlayerPreviewEnabled then return end
            if g.enableBossCastbar == false then return end
            if _G.MSUF_SetupBossCastbarPreviewEditMode then
                _G.MSUF_SetupBossCastbarPreviewEditMode()
            end
        end)
    end
end

if not _G.MSUF_BossPreviewEventDriver then
    _G.MSUF_BossPreviewEventDriver = true

    function MSUF_RefreshBossPreview(event, ...)
if type(_G.MSUF_UpdateBossCastbarPreview) ~= "function" then return end
            EnsureDB()
            local g = (MSUF_DB and MSUF_DB.general) or {}
            if not g.castbarPlayerPreviewEnabled then return end
            if g.enableBossCastbar == false then return end

            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                        _G.MSUF_UpdateBossCastbarPreview()
                    end
                    if type(_G.MSUF_SetupBossCastbarPreviewEditMode) == "function" then
                        _G.MSUF_SetupBossCastbarPreviewEditMode()
                    end
                end)
            else
                _G.MSUF_UpdateBossCastbarPreview()
                if type(_G.MSUF_SetupBossCastbarPreviewEditMode) == "function" then
                    _G.MSUF_SetupBossCastbarPreviewEditMode()
                end
            end
    end

    MSUF_EventBus_Register("INSTANCE_ENCOUNTER_ENGAGE_UNIT", "MSUF_BOSS_PREVIEW", MSUF_RefreshBossPreview)
    MSUF_EventBus_Register("ENCOUNTER_START", "MSUF_BOSS_PREVIEW", MSUF_RefreshBossPreview)
    MSUF_EventBus_Register("ENCOUNTER_END", "MSUF_BOSS_PREVIEW", MSUF_RefreshBossPreview)
    MSUF_EventBus_Register("PLAYER_ENTERING_WORLD", "MSUF_BOSS_PREVIEW", MSUF_RefreshBossPreview)
    MSUF_EventBus_Register("GROUP_ROSTER_UPDATE", "MSUF_BOSS_PREVIEW", MSUF_RefreshBossPreview)
end

if not _G.MSUF_BossPreviewApplyHooked and type(hooksecurefunc) == "function" then
    _G.MSUF_BossPreviewApplyHooked = true

    if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
        hooksecurefunc("MSUF_ApplyBossCastbarPositionSetting", function()
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                _G.MSUF_UpdateBossCastbarPreview()
            end
        end)
    end

    if type(_G.MSUF_ApplyBossCastbarsEnabled) == "function" then
        hooksecurefunc("MSUF_ApplyBossCastbarsEnabled", function()
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                _G.MSUF_UpdateBossCastbarPreview()
            end
        end)
    end
end

function MSUF_PositionPlayerCastbarPreview()
    if not MSUF_PlayerCastbarPreview then
        return
    end

    EnsureDB()
    local g = MSUF_DB.general or {}

    local offsetX = g.castbarPlayerOffsetX or 0
    local offsetY = g.castbarPlayerOffsetY or 5

    local anchorFrame
    if g.castbarPlayerDetached then
        anchorFrame = UIParent
    else
        if not UnitFrames or not UnitFrames["player"] then
            return
        end
        anchorFrame = UnitFrames["player"]
    end

    if not anchorFrame then
        return
    end

    -- Keep preview cast time text in sync with CastTime X/Y offsets (Edit Mode expects live feedback)
    if MSUF_PlayerCastbarPreview.timeText and MSUF_PlayerCastbarPreview.statusBar then
        local tx = tonumber(g.castbarPlayerTimeOffsetX)
        local ty = tonumber(g.castbarPlayerTimeOffsetY)
        if tx == nil then tx = -2 end
        if ty == nil then ty = 0 end
        MSUF_PlayerCastbarPreview.timeText:ClearAllPoints()
        MSUF_PlayerCastbarPreview.timeText:SetPoint("RIGHT", MSUF_PlayerCastbarPreview.statusBar, "RIGHT", tx, ty)
    end


    if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
        pcall(_G.MSUF_ApplyCastbarTimeTextLayout, MSUF_PlayerCastbarPreview, "player")
    end

    MSUF_PlayerCastbarPreview:ClearAllPoints()
    if g.castbarPlayerDetached then
        MSUF_PlayerCastbarPreview:SetPoint("CENTER", anchorFrame, "CENTER", offsetX, offsetY)
    else
        MSUF_PlayerCastbarPreview:SetPoint("BOTTOM", anchorFrame, "TOP", offsetX, offsetY)
    end
end

function MSUF_PositionTargetCastbarPreview()
    if not MSUF_TargetCastbarPreview then
        return
    end

    EnsureDB()
    local g = MSUF_DB.general or {}

    if MSUF_TargetCastbarPreview and MSUF_TargetCastbarPreview.timeText then
        if g.showTargetCastTime ~= false then
            MSUF_TargetCastbarPreview.timeText:Show()
            MSUF_TargetCastbarPreview.timeText:SetAlpha(1)
        else
            MSUF_TargetCastbarPreview.timeText:SetText("")
            MSUF_TargetCastbarPreview.timeText:Show()
            MSUF_TargetCastbarPreview.timeText:SetAlpha(0)
        end
    end

    -- Apply CastTime X/Y offsets to preview time text so popup sliders visibly work
    if MSUF_TargetCastbarPreview and MSUF_TargetCastbarPreview.timeText and MSUF_TargetCastbarPreview.statusBar then
        local tx = tonumber(g.castbarTargetTimeOffsetX)
        local ty = tonumber(g.castbarTargetTimeOffsetY)
        if tx == nil then tx = tonumber(g.castbarPlayerTimeOffsetX) end
        if ty == nil then ty = tonumber(g.castbarPlayerTimeOffsetY) end
        if tx == nil then tx = -2 end
        if ty == nil then ty = 0 end
        MSUF_TargetCastbarPreview.timeText:ClearAllPoints()
        MSUF_TargetCastbarPreview.timeText:SetPoint("RIGHT", MSUF_TargetCastbarPreview.statusBar, "RIGHT", tx, ty)
    end

    if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
        pcall(_G.MSUF_ApplyCastbarTimeTextLayout, MSUF_TargetCastbarPreview, "target")
    end


    local offsetX = g.castbarTargetOffsetX or 65
    local offsetY = g.castbarTargetOffsetY or -15

    local anchorFrame
    if g.castbarTargetDetached then
        anchorFrame = UIParent
    else
        if not UnitFrames or not UnitFrames["target"] then
            return
        end
        anchorFrame = UnitFrames["target"]
    end

    if not anchorFrame then
        return
    end

    MSUF_TargetCastbarPreview:ClearAllPoints()
    if g.castbarTargetDetached then
        MSUF_TargetCastbarPreview:SetPoint("CENTER", anchorFrame, "CENTER", offsetX, offsetY)
    else
        MSUF_TargetCastbarPreview:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", offsetX, offsetY)
    end
end
function MSUF_PositionFocusCastbarPreview()
    if not MSUF_FocusCastbarPreview then
        return
    end

    EnsureDB()
    local g = MSUF_DB.general or {}

    -- Apply CastTime X/Y offsets to preview time text (needed for live Edit Mode preview)
    if MSUF_FocusCastbarPreview and MSUF_FocusCastbarPreview.timeText and MSUF_FocusCastbarPreview.statusBar then
        local tx = tonumber(g.castbarFocusTimeOffsetX)
        local ty = tonumber(g.castbarFocusTimeOffsetY)
        if tx == nil then tx = tonumber(g.castbarPlayerTimeOffsetX) end
        if ty == nil then ty = tonumber(g.castbarPlayerTimeOffsetY) end
        if tx == nil then tx = -2 end
        if ty == nil then ty = 0 end
        MSUF_FocusCastbarPreview.timeText:ClearAllPoints()
        MSUF_FocusCastbarPreview.timeText:SetPoint("RIGHT", MSUF_FocusCastbarPreview.statusBar, "RIGHT", tx, ty)
    end
    
    if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
        pcall(_G.MSUF_ApplyCastbarTimeTextLayout, MSUF_FocusCastbarPreview, "focus")
    end


    local offsetX = g.castbarFocusOffsetX or (g.castbarTargetOffsetX or 65)
    local offsetY = g.castbarFocusOffsetY or (g.castbarTargetOffsetY or -15)

    local anchorFrame
    if g.castbarFocusDetached then
        anchorFrame = UIParent
    else
        if not UnitFrames or not UnitFrames["focus"] then
            return
        end
        anchorFrame = UnitFrames["focus"]
    end

    if not anchorFrame then
        return
    end

    MSUF_FocusCastbarPreview:ClearAllPoints()
    if g.castbarFocusDetached then
        MSUF_FocusCastbarPreview:SetPoint("CENTER", anchorFrame, "CENTER", offsetX, offsetY)
    else
        MSUF_FocusCastbarPreview:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", offsetX, offsetY)
    end
end

function MSUF_UpdatePlayerCastbarPreview()
    EnsureDB()
    local g = MSUF_DB.general or {}

    if not g.castbarPlayerPreviewEnabled then
        if MSUF_PlayerCastbarPreview then
            MSUF_PlayerCastbarPreview:Hide()
        end
        if MSUF_TargetCastbarPreview then
            MSUF_TargetCastbarPreview:Hide()
        end
        if MSUF_FocusCastbarPreview then
            MSUF_FocusCastbarPreview:Hide()
        end
if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
    _G.MSUF_UpdateBossCastbarPreview()
elseif _G.MSUF_BossCastbarPreview then
    _G.MSUF_BossCastbarPreview:Hide()
end

-- Stop any running popup test casts when previews are disabled.
if type(_G.MSUF_SetPlayerCastbarTestMode) == "function" then
    _G.MSUF_SetPlayerCastbarTestMode(false, true)
end
if type(_G.MSUF_SetTargetCastbarTestMode) == "function" then
    _G.MSUF_SetTargetCastbarTestMode(false, true)
end
if type(_G.MSUF_SetFocusCastbarTestMode) == "function" then
    _G.MSUF_SetFocusCastbarTestMode(false, true)
end
if type(_G.MSUF_SetBossCastbarTestMode) == "function" then
    _G.MSUF_SetBossCastbarTestMode(false, true)
end
        return
    end

    local playerPreview = MSUF_PlayerCastbarPreview or MSUF_CreatePlayerCastbarPreview()
    if playerPreview and MSUF_PositionPlayerCastbarPreview then
        MSUF_PositionPlayerCastbarPreview()
        playerPreview:Show()
        -- Keep player preview size synced to edit-mode size keys
        local w, h = MSUF_GetPlayerCastbarDesiredSize(g, 250, 18)
        MSUF_ApplyPlayerCastbarSizeAndLayout(playerPreview, g, w, h)

    end

    if UnitFrames and UnitFrames["target"] then
        local targetPreview = MSUF_TargetCastbarPreview or MSUF_CreateTargetCastbarPreview()
        if targetPreview and MSUF_PositionTargetCastbarPreview then
            MSUF_PositionTargetCastbarPreview()
            targetPreview:Show()
        end
    elseif MSUF_TargetCastbarPreview then
        MSUF_TargetCastbarPreview:Hide()
    end

    if UnitFrames and UnitFrames["focus"] then
        local focusPreview = MSUF_FocusCastbarPreview or MSUF_CreateFocusCastbarPreview()
        if focusPreview and MSUF_PositionFocusCastbarPreview then
            MSUF_PositionFocusCastbarPreview()
            focusPreview:Show()
        end
    elseif MSUF_FocusCastbarPreview then
        MSUF_FocusCastbarPreview:Hide()
    end
if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
    _G.MSUF_UpdateBossCastbarPreview()
    MSUF_SetupBossCastbarPreviewEditMode()
end

    if MSUF_UpdateCastbarVisuals then
        MSUF_UpdateCastbarVisuals()
    end
    if MSUF_UpdateCastbarTextures then
        MSUF_UpdateCastbarTextures()
    end
end

do
    -- Prefer existing helper, but keep a safe fallback.
    local ToPlain = MSUF_ToPlainNumber
    if type(ToPlain) ~= "function" then
        ToPlain = function(x)
            if x == nil then return nil end
            local t = type(x)
            if t == "number" then
                -- IMPORTANT: Duration/Timer APIs can return 'secret numbers' in Midnight/Beta.
                -- Converting through string strips the secret-tag so comparisons/arithmetic are safe.
                local s = tostring(x)
                return tonumber(s)
            end
            if t == "string" then
                return tonumber(x)
            end
            local s = tostring(x)
            return tonumber(s)
        end
    end


    _G.MSUF__castbarStyleGlobalRev = _G.MSUF__castbarStyleGlobalRev or 1
    _G.MSUF_CastbarStyleRev = _G.MSUF__castbarStyleGlobalRev
    function _G.MSUF_BumpCastbarStyleRev()
        _G.MSUF__castbarStyleGlobalRev = (_G.MSUF__castbarStyleGlobalRev or 1) + 1
        _G.MSUF_CastbarStyleRev = _G.MSUF__castbarStyleGlobalRev
    end
    local function MSUF_TryHookCastbarVisualsForStyleRev()
        if _G.MSUF__castbarStyleHooked then return end
        local fn = _G.MSUF_UpdateCastbarVisuals
        if type(fn) ~= "function" then return end

        _G.MSUF__castbarStyleHooked = true
        _G.MSUF_UpdateCastbarVisuals = function(...)
            _G.MSUF_BumpCastbarStyleRev()
            return fn(...)
        end
    end

    -- Try immediately and once more on the next frame (load order safety).
    MSUF_TryHookCastbarVisualsForStyleRev()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, MSUF_TryHookCastbarVisualsForStyleRev)
    end

    local function EnsureCastbarStyleCache(frame, force)
        if not frame then return end
        local refresh = _G.MSUF_RefreshCastbarStyleCache
        if type(refresh) ~= "function" then return end

        local rev = _G.MSUF__castbarStyleGlobalRev or 1
        if force or frame._msufCastbarStyleRev ~= rev then
            refresh(frame)
            frame._msufCastbarStyleRev = rev
        end
    end

    _G.MSUF__castTimeGlobalRev = _G.MSUF__castTimeGlobalRev or 1
    function _G.MSUF_BumpCastTimeRev()
        _G.MSUF__castTimeGlobalRev = (_G.MSUF__castTimeGlobalRev or 1) + 1
    end

    local function RefreshCastTimeCache(frame)
        if not frame or not frame.unit then
            return true
        end

        local g = MSUF_DB and MSUF_DB.general
        if not g then
            frame._msufCastTimeEnabled = true
            return true
        end

        local u = frame.unit
        local enabled = true
        if u == "player" then
            enabled = (g.showPlayerCastTime ~= false)
        elseif u == "target" then
            enabled = (g.showTargetCastTime ~= false)
        elseif u == "focus" then
            enabled = (g.showFocusCastTime ~= false)
        end

        frame._msufCastTimeEnabled = enabled and true or false
        return frame._msufCastTimeEnabled
    end

    local function EnsureCastTimeCache(frame, force)
        if not frame or not frame.unit then
            return true
        end

        local rev = _G.MSUF__castTimeGlobalRev or 1
        if force or frame._msufCastTimeRev ~= rev or frame._msufCastTimeEnabled == nil then
            RefreshCastTimeCache(frame)
            frame._msufCastTimeRev = rev
        end
        return frame._msufCastTimeEnabled ~= false
    end

    -- Override to use the cached fast-path (same behavior; far fewer calls/DB touches).
    _G.MSUF_IsCastTimeEnabled = function(frame)
        return EnsureCastTimeCache(frame, false)
    end

    -- If visuals updater exists, bump our cast-time rev when options change.
    if _G.MSUF_UpdateCastbarVisuals and not _G.__MSUF_CastTimeRevHooked then
        _G.__MSUF_CastTimeRevHooked = true
        local orig = _G.MSUF_UpdateCastbarVisuals
        _G.MSUF_UpdateCastbarVisuals = function(...)
            _G.MSUF_BumpCastTimeRev()
            local ret = orig(...)
            if type(_G.MSUF_ReanchorPlayerCastBar) == "function" then
                _G.MSUF_ReanchorPlayerCastBar()
            end
            if _G.MSUF_ApplyCastbarOutlineToAll then
                _G.MSUF_ApplyCastbarOutlineToAll(false)
            end
            return ret
        end
    end

    -- Replace manager with a tick-gated implementation (near-zero idle, even in combat).
    local oldManager = MSUF_CastbarManager
    if oldManager and oldManager.Hide then
        oldManager:Hide()
    end
    local manager = CreateFrame("Frame")
    manager.active = {}
    manager.elapsed = 0
    manager:Hide()

    local function ManagerOnUpdate(self, elapsed)
        -- Default: coarse tick (most bars are animated by Duration Objects).
        -- While a GCD bar is active we temporarily run ~60fps so the manual SetValue() path looks smooth.
        local interval = (self._msufHasGCD and 0.016) or 0.03
        self.elapsed = (self.elapsed or 0) + (elapsed or 0)
        if self.elapsed < interval then
            return
        end
        local dt = self.elapsed
        self.elapsed = 0

        local active = self.active
        if not active or not next(active) then
            self:Hide()
            return
        end

        local now = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()

        for frame in pairs(active) do
            if not frame or not frame:IsShown() or not frame.statusBar then
                active[frame] = nil
            else
                local nextTick = frame._msufNextTick
                if (not nextTick) or now >= nextTick then
                    local fi = frame._msufTickInterval or 0.10
                    local minFi = (frame.MSUF_gcdActive and 0.016) or 0.03
                    if fi < minFi then fi = minFi end
                    if fi > 0.50 then fi = 0.50 end
                    frame._msufNextTick = now + fi
                    if _G.MSUF_UpdateCastbarFrame then
                        _G.MSUF_UpdateCastbarFrame(frame, dt, now)
                    end
                end
            end
        end

        if not next(active) then
            self:Hide()
        end
    end

    manager:SetScript("OnUpdate", ManagerOnUpdate)

    -- Export as the canonical manager so existing code paths use it.
    MSUF_CastbarManager = manager

    function MSUF_RegisterCastbar(frame)
        if not frame then return end
        if not MSUF_CastbarManager or not MSUF_CastbarManager.active then return end

        if frame._msufTickInterval == nil then
            local u = frame.unit
            if u == "target" or u == "focus" then
                -- Make target/focus as snappy as player/boss (reduces perceived 5-6 frame tail).
                frame._msufTickInterval = 0.03
            else
                frame._msufTickInterval = (frame.isEmpower and 0.03) or 0.10
            end
        end
        frame._msufNextTick = 0

        EnsureCastTimeCache(frame, true)

        MSUF_CastbarManager.active[frame] = true
        MSUF_CastbarManager:Show()
    end

    function MSUF_UnregisterCastbar(frame)
        if not frame then return end
        if not MSUF_CastbarManager or not MSUF_CastbarManager.active then return end

        -- Restore base color if the optional end-of-cast fade was active.
        if type(_G.MSUF_ResetCastbarGlowFade) == "function" then
            _G.MSUF_ResetCastbarGlowFade(frame)
        end

        MSUF_CastbarManager.active[frame] = nil
        frame._msufNextTick = nil
        frame._msufZeroCount = nil

        if not next(MSUF_CastbarManager.active) then
            MSUF_CastbarManager:Hide()
        end
    end

    -- Secret-safe + cached update: time text and empower stage handling. StatusBar:SetTimerDuration animates the bar.
    function MSUF_UpdateCastbarFrame(frame, dt, now)
        if not frame or not frame.statusBar then
            return
        end

        local castTimeEnabled = EnsureCastTimeCache(frame, false)
        if frame.timeText and not castTimeEnabled then
            MSUF_SetTextIfChanged(frame.timeText, "")
        end

  
        EnsureCastbarStyleCache(frame, false)

        local now = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()

        -- GCD bar virtual cast (instant casts): driven by MSUF_CastbarGCD + CastbarManager tick.
        if frame.MSUF_gcdActive then
            if type(_G.MSUF_IsGCDBarEnabled) == "function" and not _G.MSUF_IsGCDBarEnabled() then
                if type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
                    _G.MSUF_PlayerGCDBar_Stop(frame)
                end
                return
            end

            -- Real casts/channel/empower always win.
            if frame.isEmpower then
                if type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
                    _G.MSUF_PlayerGCDBar_Stop(frame, true)
                end
                return
            end

            local u = frame.MSUF_gcdUnit or frame.unit or "player"
            if UnitCastingInfo(u) or UnitChannelInfo(u) then
                if type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
                    _G.MSUF_PlayerGCDBar_Stop(frame, true)
                end
                return
            end

            local startT = frame.MSUF_gcdStart or 0
            local dur = frame.MSUF_gcdDur or 0
            if dur <= 0 then
                if type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
                    _G.MSUF_PlayerGCDBar_Stop(frame)
                end
                return
            end

            local elapsed = now - startT
            if elapsed < 0 then elapsed = 0 end
            if elapsed > dur then elapsed = dur end

            local rem = dur - elapsed
            if rem <= 0.001 then
                if type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
                    _G.MSUF_PlayerGCDBar_Stop(frame)
                end
                return
            end

            -- Live read sub-toggles so UI changes apply immediately.
            local showTime = true
            local showSpell = true
            if type(_G.MSUF_GCD_GetSubOptions) == "function" then
                showTime, showSpell = _G.MSUF_GCD_GetSubOptions()
            end

            frame.MSUF_gcdShowTime = showTime
            frame.MSUF_gcdShowSpell = showSpell

            if frame.statusBar and frame.statusBar.SetMinMaxValues then
                frame.statusBar:SetMinMaxValues(0, dur)
            end
            if frame.statusBar and frame.statusBar.SetValue then
                frame.statusBar:SetValue(elapsed)
            end

            if frame.castText then
                if showSpell then
                    MSUF_SetTextIfChanged(frame.castText, frame.MSUF_gcdSpellName or "")
                else
                    MSUF_SetTextIfChanged(frame.castText, "")
                end
            end
            if frame.icon and frame.icon.SetTexture then
                if showSpell and frame.MSUF_gcdSpellIcon then
                    frame.icon:SetTexture(frame.MSUF_gcdSpellIcon)
                else
                    frame.icon:SetTexture(nil)
                end
            end

            if frame.timeText then
                if castTimeEnabled and showTime then
                    MSUF_SetCastTimeText(frame, rem)
                else
                    MSUF_SetTextIfChanged(frame.timeText, "")
                end
            end

            -- Optional glow fade near completion.
            if type(_G.MSUF_ApplyCastbarGlowFade) == "function" then
                _G.MSUF_ApplyCastbarGlowFade(frame, rem, dur)
            end

            return
        end


        -- Empowered casts: update value + time text and stage blink.
        if frame.isEmpower and frame.empowerStartTime and frame.empowerTotalWithGrace then
            local total = frame._msufEmpowerTotalNum or ToPlain(frame.empowerTotalWithGrace) or 0
            if total <= 0 then total = 0.01 end

            local startT = frame._msufEmpowerStartNum or ToPlain(frame.empowerStartTime) or now
            local elapsed = now - startT
            if elapsed < 0 then elapsed = 0 end
            if elapsed > total then elapsed = total end

            if frame.statusBar.SetMinMaxValues then
                frame.statusBar:SetMinMaxValues(0, total)
            end
            if frame.statusBar.SetValue then
                local v = elapsed
                if frame.reverseFill and (frame.MSUF_cachedUnifiedDirection == true) then
                    -- reverseFill already unified; leave as-is
                elseif frame.reverseFill then
                    -- value always increases; direction is handled via reverseFill.
                end
                frame.statusBar:SetValue(v)
            end

            if frame.timeText and castTimeEnabled then
                local base = frame._msufEmpowerBaseNum or ToPlain(frame.empowerTotalBase) or total
                if base <= 0 then base = total end
                local rem = base - elapsed
                if rem < 0 then rem = 0 end
                MSUF_SetCastTimeText(frame, rem)
            end

            if frame.MSUF_empowerLayoutPending and MSUF_LayoutEmpowerTicks then
                MSUF_LayoutEmpowerTicks(frame)
            end

            if frame.empowerStageEnds and frame.empowerTicks and MSUF_BlinkEmpowerTick then
                if not frame.empowerNextStage then frame.empowerNextStage = 1 end
                while frame.empowerNextStage <= #frame.empowerStageEnds do
                    local tEnd = ((frame._msufEmpowerStageEndsNum and frame._msufEmpowerStageEndsNum[frame.empowerNextStage]) or (frame.empowerStageEnds and frame.empowerStageEnds[frame.empowerNextStage]))
                    if type(tEnd) ~= "number" then tEnd = ToPlain(tEnd) end
                    if not tEnd then break end
                    if elapsed >= tEnd then
                        -- Blink if supported/enabled.
                        if MSUF_IsEmpowerStageBlinkEnabled and MSUF_IsEmpowerStageBlinkEnabled() then
                            MSUF_BlinkEmpowerTick(frame, frame.empowerNextStage)
                        end
                        frame.empowerNextStage = frame.empowerNextStage + 1
                    else
                        break
                    end
                end
            end

            -- "Glow effect": fade towards white as the empower cast approaches completion.
            if type(_G.MSUF_ApplyCastbarGlowFade) == "function" then
                local base = frame._msufEmpowerBaseNum or ToPlain(frame.empowerTotalBase) or total
                if base and base > 0 then
                    local rem = base - elapsed
                    if rem < 0 then rem = 0 end
                    _G.MSUF_ApplyCastbarGlowFade(frame, rem, base)
                end
            end

            return
        end
        do
            local nxt = frame._msufHardStopNext
            if (not nxt) or (now >= nxt) then
                frame._msufHardStopNext = now + 0.15

                local u = frame.unit
                if u and u ~= "" then
                    if frame.MSUF_isChanneled then
                        if UnitChannelInfo(u) then
                            frame._msufHardStopNoChannelSince = nil
                            frame._msufHardStopChanThresh = nil
                        else
                            local t0 = frame._msufHardStopNoChannelSince
                            if not t0 then
                                frame._msufHardStopNoChannelSince = now
                                -- Channel refresh gaps can be as large as SpellQueueWindow; keep the hard-stop threshold above that.
                                local qms = 0
                                if GetCVar then qms = tonumber(GetCVar("SpellQueueWindow") or "0") or 0 end
                                if qms < 0 then qms = 0 end
                                local thresh = 0.45
                                local q = (qms / 1000) + 0.10
                                if q > thresh then thresh = q end
                                if thresh > 0.80 then thresh = 0.80 end
                                frame._msufHardStopChanThresh = thresh
                            else
                                local thresh = frame._msufHardStopChanThresh or 0.45
                                if (now - t0) >= thresh then
                                    if frame.SetSucceeded then frame:SetSucceeded() else frame:Hide() end
                                    return
                                end
                            end
                        end
                    else
                        if UnitCastingInfo(u) or UnitChannelInfo(u) then
                            frame._msufHardStopNoCastSince = nil
                        else
                            local t0 = frame._msufHardStopNoCastSince
                            if not t0 then
                                frame._msufHardStopNoCastSince = now
                            elseif (now - t0) >= 0.25 then
                                if frame.SetSucceeded then frame:SetSucceeded() else frame:Hide() end
                                return
                            end
                        end
                    end
                end
            end
        end

        -- Duration-object path (modern API): we only maintain time text + safety stop.
        local dObj = frame.MSUF_durationObj
        if dObj and (dObj.GetRemainingDuration or dObj.GetRemaining) then
            -- If the duration object changed, re-detect timer direction for the statusbar fallback.
            if frame._msufLastDurationObj ~= dObj then
                frame._msufLastDurationObj = dObj
                frame._msufTimerAssumeCountdown = nil
            end

            local rem
            if dObj.GetRemainingDuration then
                rem = dObj:GetRemainingDuration()
            else
                rem = dObj:GetRemaining()
            end

            local remNum = ToPlain(rem)

            -- Midnight/Beta: for non-interruptible casts, Remaining can be a secret value.
            -- If we can't safely coerce it, derive remaining from the animated StatusBar value instead.
            if (not remNum) and frame.statusBar and frame.MSUF_timerDriven then
                local bar = frame.statusBar
                local okMM, minV, maxV = pcall(bar.GetMinMaxValues, bar)
                local okV, val = pcall(bar.GetValue, bar)
                if okMM and okV then
                    minV = ToPlain(minV) or 0
                    maxV = ToPlain(maxV)
                    val  = ToPlain(val)

                    if maxV and val and maxV > minV then
                        local span = maxV - minV

                        -- Detect whether bar value represents Remaining (countdown) or Elapsed (countup).
                        local assumeCountdown = frame._msufTimerAssumeCountdown
                        if assumeCountdown == nil then
                            local distMin = math.abs(val - minV)
                            local distMax = math.abs(maxV - val)
                            assumeCountdown = (distMax < distMin)
                            frame._msufTimerAssumeCountdown = assumeCountdown
                        end

                        if assumeCountdown then
                            remNum = val - minV
                        else
                            remNum = maxV - val
                        end

                        if remNum < 0 then remNum = 0 end
                        if remNum > span then remNum = span end
                    end
                end
            end

            if remNum then
                if remNum < 0 then remNum = 0 end

                if frame.timeText and castTimeEnabled then
                    MSUF_SetCastTimeText(frame, remNum)
                end

                -- "Glow effect": fade towards white as the cast approaches completion.
                if type(_G.MSUF_ApplyCastbarGlowFade) == "function" then
                    local totalNum
                    if dObj.GetTotalDuration then
                        totalNum = ToPlain(dObj:GetTotalDuration())
                    end
                    if (not totalNum) and frame.statusBar then
                        local bar = frame.statusBar
                        local okMM, minV, maxV = pcall(bar.GetMinMaxValues, bar)
                        if okMM then
                            minV = ToPlain(minV) or 0
                            maxV = ToPlain(maxV)
                            if maxV and maxV > minV then
                                totalNum = maxV - minV
                            end
                        end
                    end
                    if totalNum and totalNum > 0 then
                        _G.MSUF_ApplyCastbarGlowFade(frame, remNum, totalNum)
                    end
                end

                -- Safety: if events fail, stop updates after completion.
                if remNum <= 0.001 then
                    frame._msufZeroCount = (frame._msufZeroCount or 0) + 1
                    if frame._msufZeroCount >= 2 then
                        frame._msufZeroCount = nil
                        -- If STOP/CHANNEL_STOP was missed, unregistering alone can leave the bar stuck on screen.
                        -- Prefer the driver's cleanup/hide path when available.
                        if frame.SetSucceeded then
                            frame:SetSucceeded()
                        else
                            MSUF_UnregisterCastbar(frame)
                            if frame.Hide then frame:Hide() end
                        end
                    end
                else
                    frame._msufZeroCount = nil
                end
            elseif frame.timeText and castTimeEnabled and rem ~= nil then
                -- Last resort: show whatever the API returns (never error, helps debugging).
                local t = ""
                local okFmt, s = pcall(string.format, "%.1f", rem)
                if okFmt and s then
                    t = s
                else
                    t = tostring(rem)
                end
                MSUF_SetTextIfChanged(frame.timeText, t)
                frame._msufZeroCount = nil
            end

            return
        end

        -- Fallback: compute from stored timestamps if available.
        if frame.endTime then
            local endT = ToPlain(frame.endTime) or 0
            local remNum = endT - now
            if remNum < 0 then remNum = 0 end

            if frame.timeText and castTimeEnabled then
                MSUF_SetCastTimeText(frame, remNum)
            end

            -- "Glow effect": fade towards white as the cast approaches completion.
            if type(_G.MSUF_ApplyCastbarGlowFade) == "function" and frame.statusBar then
                local bar = frame.statusBar
                local okMM, minV, maxV = pcall(bar.GetMinMaxValues, bar)
                if okMM then
                    minV = ToPlain(minV) or 0
                    maxV = ToPlain(maxV)
                    if maxV and maxV > minV then
                        local totalNum = maxV - minV
                        if totalNum and totalNum > 0 then
                            _G.MSUF_ApplyCastbarGlowFade(frame, remNum, totalNum)
                        end
                    end
                end
            end

            if remNum <= 0.001 then
				-- Same safety as duration-object path: hide the bar if events were missed.
				if frame.SetSucceeded then
					frame:SetSucceeded()
				else
					MSUF_UnregisterCastbar(frame)
					if frame.Hide then frame:Hide() end
				end
            end
        end
    end
end
