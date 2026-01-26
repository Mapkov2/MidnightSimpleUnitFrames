-- Castbars/MSUF_CastbarUtils.lua
-- Step 10: Split low-risk shared helpers out of MSUF_Castbars.lua.
--
-- This file intentionally defines GLOBAL helpers because multiple MSUF modules
-- (Edit Mode, Boss, Options) may call into castbar helpers across files.
-- Keeping these helpers in one place prevents future drift.

local addonName, ns = ...

local function _EnsureDBSafe()
    if type(EnsureDB) == "function" then
        EnsureDB()
    end
end

-- Global: used by castbar positioning logic.
function _G.MSUF_GetAnchorFrame()
    _EnsureDBSafe()
    local g = (MSUF_DB and MSUF_DB.general) or {}

    if g.anchorToCooldown then
        local ecv = _G["EssentialCooldownViewer"]
        if ecv and ecv.IsShown and ecv:IsShown() then
            return ecv
        end
        return UIParent
    end

    local anchorName = g.anchorName
    if anchorName and anchorName ~= "" and anchorName ~= "EssentialCooldownViewer" then
        local f = _G[anchorName]
        if f and f.IsShown and f:IsShown() then
            return f
        end
    end

    return UIParent
end

-- -------------------------------------------------
-- Secret-safe interruptible vs. non-interruptible coloring
--
-- On Midnight/Beta, the notInterruptible flag returned by UnitCastingInfo/UnitChannelInfo can be a
-- *secret value*. Lua must NEVER do boolean logic on it (no `if flag then`, no `not flag`, no
-- `flag and ...`, etc.). However, C methods can safely consume it.
--
-- Trick: use StatusBarTexture:SetVertexColorFromBoolean(flag, nonInterruptibleColor, interruptibleColor).
-- -------------------------------------------------

local function _MSUF_SetSBColorCached(bar, r, g, b, a)
  if not (bar and bar.SetStatusBarColor) then return end
  a = a or 1

  -- Keep both cache schemes in sync to avoid "2nd interrupt" color regressions
  -- when some paths use the newer _msufLastColor* keys.
  local lr, lg, lb, la = bar._msufLastColorR, bar._msufLastColorG, bar._msufLastColorB, bar._msufLastColorA
  if (lr == r and lg == g and lb == b and la == a) or (bar._msufLastR == r and bar._msufLastG == g and bar._msufLastB == b and bar._msufLastA == a) then
    return
  end

  bar._msufLastColorR, bar._msufLastColorG, bar._msufLastColorB, bar._msufLastColorA = r, g, b, a
  bar._msufLastR, bar._msufLastG, bar._msufLastB, bar._msufLastA = r, g, b, a
  bar:SetStatusBarColor(r, g, b, a)
end


-- Legacy/global helper used across Driver/Visuals. Provide it here (LoD) to avoid nil regressions.
-- IMPORTANT: Do not override if core already defines it.
if type(_G.MSUF_SetStatusBarColorIfChanged) ~= "function" then
  function _G.MSUF_SetStatusBarColorIfChanged(bar, r, g, b, a)
    _MSUF_SetSBColorCached(bar, r, g, b, a)
  end
end


-- Applies the correct tint without ever boolean-testing `rawNotInterruptible` (may be secret).
-- `fallbackIsNonInterruptible` is a NORMAL Lua boolean (event-driven) used only when the C helper is unavailable.
function _G.MSUF_Castbar_ApplyNonInterruptibleTint(frame, rawNotInterruptible,
  nonIntR, nonIntG, nonIntB, nonIntA,
  intR, intG, intB, intA,
  fallbackIsNonInterruptible)

  local sb = frame and frame.statusBar
  if not sb then return false end

  local wantNI = (fallbackIsNonInterruptible == true)

  local ar = wantNI and nonIntR or intR
  local ag = wantNI and nonIntG or intG
  local ab = wantNI and nonIntB or intB
  local aa = wantNI and (nonIntA or 1) or (intA or 1)

  local tex = sb.GetStatusBarTexture and sb:GetStatusBarTexture()
  local usedC = false

  if tex and tex.SetVertexColorFromBoolean and CreateColor then
    -- IMPORTANT (Midnight/Beta, secret-safe):
    --  - Never boolean-test `rawNotInterruptible` in Lua (may be secret).
    --  - Never pass nil into SetVertexColorFromBoolean (hard error).
    -- We pass the raw value straight into the C method when present; otherwise we use a normal Lua boolean fallback.
    local nonCol = CreateColor(nonIntR, nonIntG, nonIntB, nonIntA or 1)
    local intCol = CreateColor(intR, intG, intB, intA or 1)

    local v = rawNotInterruptible
    if v == nil then
      v = (wantNI == true)
    end

    tex:SetVertexColorFromBoolean(v, nonCol, intCol)
    usedC = true
  end

  if not usedC then
    -- Pure StatusBar color fallback.
    _MSUF_SetSBColorCached(sb, ar, ag, ab, aa)
  else
    -- IMPORTANT (0-regression fix): keep the StatusBar color caches in sync even when
    -- we color via vertex tint. Otherwise later calls that rely on cached colors
    -- (e.g. interrupt feedback) may early-return and skip applying red on "2nd interrupt".
    sb._msufLastColorR, sb._msufLastColorG, sb._msufLastColorB, sb._msufLastColorA = ar, ag, ab, aa
    sb._msufLastR, sb._msufLastG, sb._msufLastB, sb._msufLastA = ar, ag, ab, aa
  end

  -- Also keep glow-base tracking stable across both tint paths.
  if not sb._msufGlowSkipBase then
    local br, bg, bb, ba = sb._msufGlowBaseR, sb._msufGlowBaseG, sb._msufGlowBaseB, sb._msufGlowBaseA
    if br ~= ar or bg ~= ag or bb ~= ab or ba ~= aa then
      sb._msufGlowBaseR, sb._msufGlowBaseG, sb._msufGlowBaseB, sb._msufGlowBaseA = ar, ag, ab, aa
      sb._msufGlowLastP = nil
    end
  end

  return usedC
end


-- -------------------------------------------------
-- Step 6: Shared castbar APPLY helper (maintainability + less drift)
-- Single place to:
--  - set icon/text
--  - apply durationObj to StatusBar via SetTimerDuration (and direction)
--  - set MSUF_isChanneled/MSUF_durationObj flags
--  - register + update time text (when available)
--
-- IMPORTANT: This helper is SECRET-SAFE:
--  - it does not compare spellId / castGUID / spellName
--  - it only consumes the provided state and writes it to the frame
-- -------------------------------------------------

local function _MSUF_SetTextIfChanged(fs, s)
    if not (fs and fs.SetText) then return end
    if type(_G.MSUF_SetTextIfChanged) == "function" then
        _G.MSUF_SetTextIfChanged(fs, s or "")
    else
        fs:SetText(s or "")
    end
end

local function _MSUF_GetReverseFill(frame, state, isChanneled)
    -- Prefer the engine/state-provided reverseFill when present.
    if state and state.reverseFill ~= nil then
        return (state.reverseFill == true)
    end
    -- Otherwise defer to the user setting logic.
    if type(_G.MSUF_GetCastbarReverseFillForFrame) == "function" then
        local ok, rev = pcall(_G.MSUF_GetCastbarReverseFillForFrame, frame, isChanneled and true or false)
        if ok and rev ~= nil then
            return (rev == true)
        end
    end
    return false
end

-- Apply a normal CAST/CHANNEL state that has a durationObj.
-- Returns true when it applied and showed the bar; false when state is not applicable.
function _G.MSUF_Castbar_ApplyActiveDuration(frame, state, opts)
    if not (frame and state and state.active) then return false end
    local durObj = state.durationObj
    local spellName = state.spellName
    if durObj == nil or not spellName then return false end

    opts = opts or {}
    local resetRuntime = (opts.resetRuntime ~= false)

    local isChanneled = (state.castType == "CHANNEL")
    frame.MSUF_durationObj = durObj
    frame.MSUF_isChanneled = isChanneled and true or false
    frame.MSUF_channelDirect = (isChanneled and (frame.unit == "target" or frame.unit == "focus")) and true or nil

    frame.interrupted = nil

    -- Basic visuals
    if frame.icon and state.icon then
        frame.icon:SetTexture(state.icon)
    end
    if frame.castText then
        _MSUF_SetTextIfChanged(frame.castText, state.text or spellName or "")
    end

    -- Reset hotpath caches (prevents "stale last value" issues after retargeting / refresh)
    if resetRuntime then
        frame.castDuration = nil
        frame.castElapsed  = nil
        frame.MSUF_timerDriven = nil
        frame.MSUF_timerRangeSet = nil
        frame._msufLastSBValue = nil
        frame.MSUF_channelDirect = (isChanneled and (frame.unit == "target" or frame.unit == "focus")) and true or nil
        frame._msufHardStopNoChannelSince = nil
        frame._msufHardStopNoCastSince = nil
    end

    local rev = _MSUF_GetReverseFill(frame, state, isChanneled)

    -- Apply timer duration + direction (supports new SetTimerDuration direction signatures)
    local okTimer = false
    local sb = frame.statusBar
    if sb then
        if type(_G.MSUF_ApplyCastbarTimerDirection) == "function" then
            okTimer = (_G.MSUF_ApplyCastbarTimerDirection(sb, durObj, rev) == true)
        elseif type(_G.MSUF_SetStatusBarTimerDuration) == "function" then
            okTimer = (_G.MSUF_SetStatusBarTimerDuration(sb, durObj, rev) == true)
            if sb.SetReverseFill then
                pcall(sb.SetReverseFill, sb, rev and true or false)
            end
        elseif sb.SetTimerDuration then
            -- Cache which signature works (some builds expect numeric direction; others boolean).
            local mode = _G.__MSUF_TimerDurationMode
            if mode ~= nil then
                okTimer = (pcall(sb.SetTimerDuration, sb, durObj, mode) == true)
            else
                local ok0 = pcall(sb.SetTimerDuration, sb, durObj, 0)
                if ok0 then
                    _G.__MSUF_TimerDurationMode = 0
                    okTimer = true
                else
                    local okB = pcall(sb.SetTimerDuration, sb, durObj, true)
                    if okB then
                        _G.__MSUF_TimerDurationMode = true
                        okTimer = true
                    end
                end
            end
            if sb.SetReverseFill then
                pcall(sb.SetReverseFill, sb, rev and true or false)
            end
        elseif sb.SetReverseFill then
            pcall(sb.SetReverseFill, sb, rev and true or false)
        end
    end
    frame.MSUF_timerDriven = okTimer and true or false

    if frame.UpdateColorForInterruptible then
        frame:UpdateColorForInterruptible()
    end

    if type(_G.MSUF_RegisterCastbar) == "function" and opts.skipRegister ~= true then
        _G.MSUF_RegisterCastbar(frame)
    end

    if frame.timeText and opts.skipTimeText ~= true and type(_G.MSUF_UpdateCastTimeText_FromStatusBar) == "function" then
        _G.MSUF_UpdateCastTimeText_FromStatusBar(frame)
    end

    if frame.Show then frame:Show() end
    return true
end
local function MSUF_EnsureCastbarShakeAnimation(frame)
    if not frame or frame.MSUF_ShakeGroup then
        return
    end

    local group = frame:CreateAnimationGroup("MSUF_ShakeGroup")
    group:SetLooping("NONE")

    local a1 = group:CreateAnimation("Translation")
    a1:SetOffset(4, 0)
    a1:SetDuration(0.05)
    a1:SetOrder(1)

    local a2 = group:CreateAnimation("Translation")
    a2:SetOffset(-8, 0)
    a2:SetDuration(0.10)
    a2:SetOrder(2)

    local a3 = group:CreateAnimation("Translation")
    a3:SetOffset(4, 0)
    a3:SetDuration(0.05)
    a3:SetOrder(3)

    frame.MSUF_ShakeGroup = group
    frame.MSUF_ShakeA1 = a1
    frame.MSUF_ShakeA2 = a2
    frame.MSUF_ShakeA3 = a3
end

-- Fallback shake implementation (boss castbars can suppress Translation animations on some clients).
-- This nudges the frame's anchor points briefly and then restores them.
local function MSUF_PlayCastbarShake_Manual(frame, strength)
    if not frame or type(frame.GetNumPoints) ~= "function" or type(frame.GetPoint) ~= "function" then
        return
    end
    if frame._msufShakeManualActive then
        return
    end
    if not _G.C_Timer or not _G.C_Timer.After then
        return
    end

    frame._msufShakeManualActive = true

    local points = frame._msufShakePoints
    if not points then
        points = {}
        frame._msufShakePoints = points
    else
        -- wipe without requiring global wipe()
        for k in pairs(points) do points[k] = nil end
    end

    local num = frame:GetNumPoints() or 0
    if num < 1 then
        points[1] = { "CENTER", UIParent, "CENTER", 0, 0 }
    else
        for i = 1, num do
            local p, rel, rp, x, y = frame:GetPoint(i)
            points[i] = { p, rel, rp, x or 0, y or 0 }
        end
    end

    local function Apply(dx)
        if not frame or not frame.SetPoint then return end
        frame:ClearAllPoints()
        for i = 1, #points do
            local pt = points[i]
            if pt and pt[1] then
                frame:SetPoint(pt[1], pt[2], pt[3], (pt[4] or 0) + dx, pt[5] or 0)
            end
        end
    end

    -- Temporarily disable clamping if needed (clamping can counteract point nudges).
    local wasClamped = nil
    if frame.IsClampedToScreen and frame.SetClampedToScreen then
        wasClamped = frame:IsClampedToScreen()
        if wasClamped then frame:SetClampedToScreen(false) end
    end

    local half = strength / 2
    Apply(half)
    _G.C_Timer.After(0.05, function() Apply(-strength) end)
    _G.C_Timer.After(0.15, function() Apply(half) end)
    _G.C_Timer.After(0.20, function()
        Apply(0)
        if frame and wasClamped ~= nil and frame.SetClampedToScreen then
            frame:SetClampedToScreen(wasClamped)
        end
        if frame then frame._msufShakeManualActive = nil end
    end)
end

function _G.MSUF_PlayCastbarShake(frame)
    if not frame then
        return
    end

    _EnsureDBSafe()
    local g = (MSUF_DB and MSUF_DB.general) or {}

    if g.castbarInterruptShake == false then
        return
    end

    local strength = tonumber(g.castbarShakeStrength) or 8
    if strength < 0 then strength = 0 end
    if strength > 30 then strength = 30 end
    if strength <= 0 then
        return
    end
    local half = strength / 2

    -- IMPORTANT: In Midnight/Beta some clients suppress Translation animations on clamped UI frames.
    -- Our castbars (Target/Focus/Boss + previews) are clamped, so we prefer the deterministic manual shake
    -- whenever the frame is clamped (or explicitly marked for manual shake).
    local isBoss = (frame.unit and type(frame.unit) == "string" and frame.unit:match("^boss"))
    local isClamped = (frame.IsClampedToScreen and frame.SetClampedToScreen and frame:IsClampedToScreen())
    if frame.MSUF_forceManualShake or isBoss or isClamped then
        MSUF_PlayCastbarShake_Manual(frame, strength)
        return
    end

    MSUF_EnsureCastbarShakeAnimation(frame)

    -- Apply current strength to the translation animations (so the slider is live).
    if frame.MSUF_ShakeA1 and frame.MSUF_ShakeA1.SetOffset then
        frame.MSUF_ShakeA1:SetOffset(half, 0)
    end
    if frame.MSUF_ShakeA2 and frame.MSUF_ShakeA2.SetOffset then
        frame.MSUF_ShakeA2:SetOffset(-strength, 0)
    end
    if frame.MSUF_ShakeA3 and frame.MSUF_ShakeA3.SetOffset then
        frame.MSUF_ShakeA3:SetOffset(half, 0)
    end

    if frame.MSUF_ShakeGroup then
        frame.MSUF_ShakeGroup:Stop()
        frame.MSUF_ShakeGroup:Play()
    end
end

function _G.MSUF_GetInterruptibleCastColor()
    _EnsureDBSafe()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local r = tonumber(g.castbarInterruptibleR)
    local gg = tonumber(g.castbarInterruptibleG)
    local b = tonumber(g.castbarInterruptibleB)
    if r and gg and b then
        return r, gg, b, 1
    end
end

function _G.MSUF_GetNonInterruptibleCastColor()
    _EnsureDBSafe()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local r = tonumber(g.castbarNonInterruptibleR)
    local gg = tonumber(g.castbarNonInterruptibleG)
    local b = tonumber(g.castbarNonInterruptibleB)
    if r and gg and b then
        return r, gg, b, 1
    end
end

-- "Glow effect" (Options -> Castbars -> Behavior): end-of-cast fade to white.
-- NOTE: This is intentionally texture-agnostic and does not rely on background/foreground textures matching.
-- It simply blends the current fill color towards white as the cast approaches completion.

local function _MSUF_ToPlainNumber(x)
    local fn = _G.MSUF_ToPlainNumber
    if type(fn) == "function" then
        return fn(x)
    end
    local ok, n = pcall(tonumber, x)
    if ok then return n end
    return nil
end

local function _MSUF_IsGlowFadeEnabled()
    _EnsureDBSafe()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    if g and g.castbarShowGlow == false then
        return false
    end
    -- default ON
    return true
end

function _G.MSUF_ResetCastbarGlowFade(frame)
    if not frame or not frame.statusBar then return end
    local sb = frame.statusBar
    if not sb._msufGlowApplied then
        return
    end
    local br, bg, bb, ba = sb._msufGlowBaseR, sb._msufGlowBaseG, sb._msufGlowBaseB, sb._msufGlowBaseA
    if type(br) ~= "number" or type(bg) ~= "number" or type(bb) ~= "number" then
        sb._msufGlowApplied = nil
        sb._msufGlowLastP = nil
        return
    end
    if ba == nil then ba = 1 end

    sb._msufGlowSkipBase = true
    if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
        _G.MSUF_SetStatusBarColorIfChanged(sb, br, bg, bb, ba)
    else
        sb:SetStatusBarColor(br, bg, bb, ba)
    end
    sb._msufGlowSkipBase = nil

    sb._msufGlowApplied = nil
    sb._msufGlowLastP = nil
end

function _G.MSUF_ApplyCastbarGlowFade(frame, remaining, total)
    if not frame or not frame.statusBar then return end

    -- Real casts: always apply (when enabled).
    -- Edit Mode previews / dummy casts: also apply while MSUF Edit Mode is active.
    if (frame._msufIsPreview or frame.MSUF_testMode) and not _G.MSUF_UnitEditModeActive then
        return
    end
    if frame.interrupted then
        return
    end
    if frame.interruptFeedbackEndTime then
        local now = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
        if now < frame.interruptFeedbackEndTime then
            return
        end
    end

    if not _MSUF_IsGlowFadeEnabled() then
        _G.MSUF_ResetCastbarGlowFade(frame)
        return
    end

    local rem = _MSUF_ToPlainNumber(remaining)
    local tot = _MSUF_ToPlainNumber(total)
    if type(rem) ~= "number" or type(tot) ~= "number" or tot <= 0 then
        return
    end

    if rem < 0 then rem = 0 end
    if rem > tot then rem = tot end

    local p = 1 - (rem / tot)
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    -- Ease-in so the bar only becomes noticeably white near the end.
    p = p * p

    local sb = frame.statusBar
    -- Throttle updates (performance): only recolor when the blend factor changes enough.
    local lastP = sb._msufGlowLastP
    if type(lastP) == "number" then
        local d = p - lastP
        if d < 0 then d = -d end
        if d < 0.02 then
            return
        end
    end
    sb._msufGlowLastP = p

    local br, bg, bb, ba = sb._msufGlowBaseR, sb._msufGlowBaseG, sb._msufGlowBaseB, sb._msufGlowBaseA
    if type(br) ~= "number" or type(bg) ~= "number" or type(bb) ~= "number" then
        -- Fallback: capture current color as base (best-effort).
        if sb.GetStatusBarColor then
            local ok, rr, gg, bb2, aa2 = pcall(sb.GetStatusBarColor, sb)
            if ok then
                br, bg, bb, ba = rr, gg, bb2, aa2
                sb._msufGlowBaseR, sb._msufGlowBaseG, sb._msufGlowBaseB, sb._msufGlowBaseA = br, bg, bb, ba
            end
        end
    end
    if type(br) ~= "number" or type(bg) ~= "number" or type(bb) ~= "number" then
        return
    end
    if ba == nil then ba = 1 end

    local rr = br + (1 - br) * p
    local gg = bg + (1 - bg) * p
    local bb3 = bb + (1 - bb) * p

    sb._msufGlowSkipBase = true
    if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
        _G.MSUF_SetStatusBarColorIfChanged(sb, rr, gg, bb3, ba)
    else
        sb:SetStatusBarColor(rr, gg, bb3, ba)
    end
    sb._msufGlowSkipBase = nil

    sb._msufGlowApplied = true
end


-- ============================================================================
-- Phase 2.1 (Scaffolding): Apply-Layer wrappers (wrapper-only, ultra low risk)
-- ----------------------------------------------------------------------------
-- Intent:
--   Provide a clear, single "apply surface" that callsites can use without
--   changing behavior. These wrappers MUST stay thin pass-throughs for now.
--   No reordering, no new logic, no new state.
--
-- Notes:
--   - `state` is currently optional and may be nil. It exists to support future
--     gradual migration to a clearer Snapshot/Apply split.
--   - To avoid hot-path allocations, wrappers accept optional positional args.
-- ============================================================================

function _G.MSUF_CB_ApplyColor(frame, state)
    if frame and frame.UpdateColorForInterruptible then
        -- Keep existing SSoT for interrupt/color caches inside UpdateColorForInterruptible().
        return frame:UpdateColorForInterruptible()
    end
end

function _G.MSUF_CB_ApplyTexts(frame, state, castText, timeText)
    if not frame then return end

    -- Optional state support (no allocations required).
    if state ~= nil then
        if castText == nil then castText = state.castText end
        if timeText == nil then timeText = state.timeText end
    end

    if castText ~= nil and frame.castText then
        _MSUF_SetTextIfChanged(frame.castText, castText)
    end
    if timeText ~= nil and frame.timeText then
        _MSUF_SetTextIfChanged(frame.timeText, timeText)
    end
end

function _G.MSUF_CB_ApplyFillAndTime(frame, state, ...)
    if not frame then return end
    if type(_G.MSUF_Castbar_ApplyActiveDuration) == "function" and state ~= nil then
        -- Pass-through to the existing shared apply helper (no behavior changes here).
        return _G.MSUF_Castbar_ApplyActiveDuration(frame, state, ...)
    end
end

function _G.MSUF_CB_ApplyEmpowerTicks(frame, state, ...)
    -- Forward to the existing empower tick renderer (SSoT lives there).
    if type(_G.MSUF_LayoutEmpowerTicks) == "function" then
        return _G.MSUF_LayoutEmpowerTicks(frame, ...)
    end
end


-- Stop/Reset reason enum (local, stable strings; used only to select existing stop-path behavior).
local MSUF_CB_STOP_REASON = {
    SUCCEEDED   = "SUCCEEDED",
    FAILED      = "FAILED",
    INTERRUPTED = "INTERRUPTED",
    STOPPED     = "STOPPED",
    HARDHIDE    = "HARDHIDE",
}

-- Centralized stop/reset helper (Phase 2.2):
-- This is intentionally a thin 1:1 extraction of existing duplicated stop blocks.
-- It does NOT make color decisions (interrupt/SSoT remains elsewhere).

function _G.MSUF_CB_ResetStateOnStop(frame, reasonOrState, opts)
    if not frame then return end
    opts = opts or {}

    local reason = reasonOrState
    if type(reasonOrState) == "table" then
        reason = reasonOrState.reason or reasonOrState.kind or reasonOrState[1]
    end
    if type(reason) ~= "string" then
        reason = MSUF_CB_STOP_REASON.STOPPED
    end

    -- NOTE: We intentionally keep per-reason behavior differences (what gets cleared/hidden),
    -- to ensure 0-regression vs the prior copy/paste blocks.

    if reason == MSUF_CB_STOP_REASON.HARDHIDE then
        -- 1:1 with the "castbar disabled" early return block in Driver OnEvent.
        frame:SetScript("OnUpdate", nil)
        if MSUF_UnregisterCastbar then
            MSUF_UnregisterCastbar(frame)
        end
        frame.MSUF_durationObj = nil
        frame.MSUF_isChanneled = nil
        frame.MSUF_channelDirect = nil
        frame.MSUF_timerDriven = nil
        frame.MSUF_timerRangeSet = nil
        frame._msufLastSBValue = nil
        frame.castDuration = nil
        frame.castElapsed = nil
        if frame.timeText then
            _G.MSUF_CB_ApplyTexts(frame, nil, nil, "")
        end
        if frame.latencyBar then
            frame.latencyBar:Hide()
        end
        frame:Hide()
        return
    end

    if reason == MSUF_CB_STOP_REASON.STOPPED then
        -- 1:1 with the deferred stop-reset in frame:Cast() (when no active state).
        frame:SetScript("OnUpdate", nil)
        if MSUF_UnregisterCastbar then
            MSUF_UnregisterCastbar(frame)
        end
        frame.MSUF_durationObj = nil
        frame.castDuration = nil
        frame.castElapsed  = nil
        frame.MSUF_timerDriven = nil
        frame.MSUF_timerRangeSet = nil
        frame.MSUF_isChanneled = nil
        frame.MSUF_channelDirect = nil
        if frame.timeText then
            _G.MSUF_CB_ApplyTexts(frame, nil, nil, "")
        end
        if frame.castText then
            _G.MSUF_CB_ApplyTexts(frame, nil, "", nil)
        end
        if frame.latencyBar then
            frame.latencyBar:Hide()
        end
        if not frame.interrupted then
            frame:Hide()
        end
        return
    end

    -- Shared core stop-reset (SUCCEEDED/FAILED/INTERRUPTED):
    -- This matches the duplicated blocks previously in SetSucceeded/SetInterrupted.

    if frame.isEmpower then
        if type(_G.MSUF_ClearEmpowerState) == "function" then
            _G.MSUF_ClearEmpowerState(frame)
        elseif type(MSUF_ClearEmpowerState) == "function" then
            MSUF_ClearEmpowerState(frame)
        end
    end

    frame:SetScript("OnUpdate", nil)

    local t = frame.hideTimer
    if t and t.Cancel then t:Cancel() end
    frame.hideTimer = nil

    t = frame.succeededTimer
    if t and t.Cancel then t:Cancel() end
    frame.succeededTimer = nil

    t = frame.timer
    if t and t.Cancel then t:Cancel() end
    frame.timer = nil

    if MSUF_UnregisterCastbar then
        MSUF_UnregisterCastbar(frame)
    end

    frame.MSUF_durationObj = nil
    frame.MSUF_isChanneled = nil
    frame.MSUF_channelDirect = nil
    frame.MSUF_timerDriven = nil
    frame.MSUF_timerRangeSet = nil

    if reason == MSUF_CB_STOP_REASON.INTERRUPTED then
        if _G.MSUF_ClearCastbarTimerDuration and frame.statusBar then
            _G.MSUF_ClearCastbarTimerDuration(frame.statusBar)
        end
    end

    frame.castDuration = nil
    frame.castElapsed  = nil

    if reason == MSUF_CB_STOP_REASON.SUCCEEDED or reason == MSUF_CB_STOP_REASON.FAILED then
        if frame.castText then
            _G.MSUF_CB_ApplyTexts(frame, nil, "", nil)
        end
        if frame.timeText then
            _G.MSUF_CB_ApplyTexts(frame, nil, nil, "")
        end
        frame:Hide()
        return
    end

    -- INTERRUPTED: do not apply colors here (interrupt/SSoT handles it).
    -- Text/Show/Hold timer remain in the caller (SetInterrupted), matching the old code.
end
