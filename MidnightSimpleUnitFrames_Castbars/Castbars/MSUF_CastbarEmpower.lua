-- Castbars/MSUF_CastbarEmpower.lua
-- All public functions exported to _G for cross-file resolution.

local MSUF_FastCall = _G.MSUF_FastCall or function(...) return pcall(...) end
local _EnsureDBLazy = _G.MSUF_EnsureDBLazy or function()
    if not MSUF_DB and type(EnsureDB) == "function" then EnsureDB() end
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
    _EnsureDBLazy()  -- P3 Fix #14: lazy guard
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
    _EnsureDBLazy()  -- P3 Fix #14: lazy guard
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

    -- Quick Win #3: Pre-cache plain numbers so the per-tick update path never calls ToPlain().
    -- MSUF_BuildEmpowerTimeline already returns plain Lua numbers, but we tonumber() for safety.
    self._msufEmpowerStartNum    = tonumber(self.empowerStartTime) or now
    self._msufEmpowerTotalNum    = tonumber(self.empowerTotalWithGrace) or 0
    self._msufEmpowerBaseNum     = tonumber(self.empowerTotalBase) or self._msufEmpowerTotalNum
    if tl.stageEnds then
        local nums = {}
        for i = 1, #tl.stageEnds do
            nums[i] = tonumber(tl.stageEnds[i])
        end
        self._msufEmpowerStageEndsNum = nums
    else
        self._msufEmpowerStageEndsNum = nil
    end
    local rf = _G.MSUF_GetReverseFillSafe(self, true)
    local empDObj = nil
    if type(UnitCastingDuration) == "function" then
        local okD
        okD, empDObj = MSUF_FastCall(UnitCastingDuration, "player")
        if not okD then empDObj = nil end
    end
    _G.MSUF_ApplyTimerAndFill(self.statusBar, empDObj, rf)

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
    if type(_G.MSUF_EnsureCastbarManager) == "function" then _G.MSUF_EnsureCastbarManager() end
    if type(_G.MSUF_RegisterCastbar) == "function" then _G.MSUF_RegisterCastbar(self) end
    if type(_G.MSUF_UpdateCastbarFrame) == "function" then _G.MSUF_UpdateCastbarFrame(self, 0) end

    local _UpdateColor = _G.MSUF_PlayerCastbar_UpdateColorForInterruptible
    if type(_UpdateColor) == "function" then _UpdateColor(self) end
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
        if type(_G.MSUF_UnregisterCastbar) == "function" then _G.MSUF_UnregisterCastbar(self) end
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

---------------------------------------------------------------------------
-- _G exports
---------------------------------------------------------------------------
_G.MSUF_BuildEmpowerTimeline           = MSUF_BuildEmpowerTimeline
_G.MSUF_BlinkEmpowerTick               = MSUF_BlinkEmpowerTick
_G.MSUF_LayoutEmpowerTicks             = MSUF_LayoutEmpowerTicks
_G.MSUF_EnsureEmpowerTicks             = MSUF_EnsureEmpowerTicks
_G.MSUF_EnsureEmpowerStageSegments     = MSUF_EnsureEmpowerStageSegments
_G.MSUF_LayoutEmpowerStageSegments     = MSUF_LayoutEmpowerStageSegments
_G.MSUF_GetUnifiedDirection            = MSUF_GetUnifiedDirection
_G.MSUF_GetUnifiedFillEnabled          = MSUF_GetUnifiedFillEnabled
_G.MSUF_IsEmpowerColorStagesEnabled    = MSUF_IsEmpowerColorStagesEnabled
_G.MSUF_GetEmpowerStageBlinkTime       = MSUF_GetEmpowerStageBlinkTime
_G.MSUF_IsEmpowerStageBlinkEnabled     = MSUF_IsEmpowerStageBlinkEnabled
_G.MSUF_PlayerCastbar_EmpowerStart     = MSUF_PlayerCastbar_EmpowerStart
_G.MSUF_PlayerCastbar_ClearEmpower     = MSUF_PlayerCastbar_ClearEmpower
