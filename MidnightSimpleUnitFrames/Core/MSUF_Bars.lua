-- Core/MSUF_Bars.lua — Bar subsystems: self-heal prediction, gradients, absorb bars, reverse fill
-- Merged from MSUF_SelfHealPred.lua + MSUF_Gradients.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber = type, tonumber

-- From main file (ns.Bars exports)
local MSUF_ApplyAbsorbOverlayColor     = ns.Bars._ApplyAbsorbOverlayColor
local MSUF_ApplyHealAbsorbOverlayColor = ns.Bars._ApplyHealAbsorbOverlayColor
local MSUF_ResetBarZero                = ns.Bars._ResetBarZero

-- ══════════════════════════════════════════════════════════════
-- Self-heal prediction overlay (was MSUF_SelfHealPred.lua)
-- ══════════════════════════════════════════════════════════════
local _MSUF_SelfHealPredCalc -- nil = unknown, false = unavailable, table = calc
local function _MSUF_GetSelfHealPredCalc()
    if _MSUF_SelfHealPredCalc ~= nil then return _MSUF_SelfHealPredCalc end
    _MSUF_SelfHealPredCalc = false
    local fn = _G and _G.CreateUnitHealPredictionCalculator
    if type(fn) == "function" then
        local ok, calc
        if _G and type(_G.MSUF_FastCall) == "function" then
            ok, calc = _G.MSUF_FastCall(fn)
        else
            ok, calc = pcall(fn)
        end
        if ok and calc then
            _MSUF_SelfHealPredCalc = calc
        end
    end
    return _MSUF_SelfHealPredCalc
end

local function _MSUF_GetIncomingHealsFromPlayer(unit)
    if not unit then return 0 end

    -- Fast path if the classic C-API is available.
    local fnInc = _G and _G.UnitGetIncomingHeals
    if type(fnInc) == "function" then
        local ok, v
        if _G and type(_G.MSUF_FastCall) == "function" then
            ok, v = _G.MSUF_FastCall(fnInc, unit, "player")
        else
            ok, v = pcall(fnInc, unit, "player")
        end
        if ok and type(v) == "number" then
            return v
        end
    end

    -- Fallback: detailed prediction calculator.
    local calc = _MSUF_GetSelfHealPredCalc()
    local fnDet = _G and _G.UnitGetDetailedHealPrediction
    if calc and type(fnDet) == "function" then
        local ok
        if _G and type(_G.MSUF_FastCall) == "function" then
            ok = select(1, _G.MSUF_FastCall(fnDet, unit, "player", calc))
        else
            ok = pcall(fnDet, unit, "player", calc)
        end
        if ok and calc.GetIncomingHeals then
            local total, fromHealer = calc:GetIncomingHeals()
            if type(fromHealer) == "number" then return fromHealer end
            if type(total) == "number" then return total end
        end
    end

    return 0
end

local _msufSelfHealCalc = nil
local _msufSelfHealPredPixelCalcBar = nil

local function _MSUF_EnsureSelfHealPredPixelCalcBar()
    local bar = _msufSelfHealPredPixelCalcBar
    if bar then
        return bar
    end

    bar = _G.CreateFrame("StatusBar", "MSUF_SelfHealPredPixelCalcBar", _G.UIParent)
    bar:SetSize(1, 1)
    bar:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", -5000, 0)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetAlpha(0)
    bar:Show()

    _msufSelfHealPredPixelCalcBar = bar
    return bar
end

local function _MSUF_GetIncomingSelfHeals(unit)
    unit = unit or "player"

    local calc = _msufSelfHealCalc
    if not calc and _G.CreateUnitHealPredictionCalculator then
        calc = _G.CreateUnitHealPredictionCalculator()
        _msufSelfHealCalc = calc
    end

    if calc and _G.UnitGetDetailedHealPrediction then
        local data = _G.UnitGetDetailedHealPrediction(unit, "player", calc)
        if data and type(data) == "table" then
            -- Prefer the clamped amount if provided, so it never visually overflows missing health.
            -- IMPORTANT (Midnight/Secret-safe): never use secret numbers in boolean context (no 'or' fallback).
            local v = data.clampedIncomingHealsFromHealer
            if type(v) ~= "number" then
                v = data.incomingHealsFromHealer
            end
            if type(v) == "number" then
                return v
            end
        end
    end

    if _G.UnitGetIncomingHeals then
        local v = _G.UnitGetIncomingHeals(unit, "player")
        if type(v) == "number" then
            return v
        end
    end

    return 0
end

local function _MSUF_HideSelfHealPredBar(frame)
    if not frame or not frame.selfHealPredBar then return end
    local bar = frame.selfHealPredBar
    bar:Hide()
    bar._msufSelfHealPredLastW = nil
    bar._msufSelfHealPredAnchorTex = nil
    bar._msufSelfHealPredAnchorRev = nil
end


local function _MSUF_UpdateSelfHealPrediction(frame, unit, maxHP, hp)
    local g = MSUF_DB and MSUF_DB.general
    if not g or not g.showSelfHealPrediction then
        _MSUF_HideSelfHealPredBar(frame)
        return
    end

    if not frame or not frame.selfHealPredBar or not frame.hpBar then return end
    local predBar = frame.selfHealPredBar
    local hpBar = frame.hpBar

    -- Early outs
    if frame.IsShown and not frame:IsShown() then
        _MSUF_HideSelfHealPredBar(frame)
        return
    end
    if hpBar.IsShown and not hpBar:IsShown() then
        _MSUF_HideSelfHealPredBar(frame)
        return
    end

    local hpTex = hpBar.GetStatusBarTexture and hpBar:GetStatusBarTexture()
    if not hpTex then
        _MSUF_HideSelfHealPredBar(frame)
        return
    end

    -- NOTE (Midnight/secret-safe):
    -- - Do NOT do ANY arithmetic or comparisons on incoming-heal numbers (can be secret-tainted).
    -- - Do NOT read/compare HP texture width.
    -- Instead: render a second statusbar segment anchored to the current HP texture edge.
    -- The statusbar fill itself computes the pixel length (inc/maxHP) internally.
    -- Overflow (inc > missing) is clipped by the dedicated clip-frame created at unitframe build.

    -- Sync size to full HP bar size (frame dimensions are safe numbers).
    if hpBar.GetWidth and hpBar.GetHeight then
        local w = hpBar:GetWidth()
        local h = hpBar:GetHeight()
        if type(w) == "number" and type(h) == "number" then
            predBar:SetSize(w, h)
        end
    end

    -- Sync reverse fill + anchor to the HP texture edge.
    local rev = (hpBar.GetReverseFill and hpBar:GetReverseFill()) or false
    if predBar._msufSelfHealPredAnchorTex ~= hpTex or predBar._msufSelfHealPredAnchorRev ~= rev then
        predBar:ClearAllPoints()
        if rev then
            predBar:SetPoint("TOPRIGHT", hpTex, "TOPLEFT", 0, 0)
            predBar:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMLEFT", 0, 0)
        else
            predBar:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", 0, 0)
            predBar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)
        end
        predBar._msufSelfHealPredAnchorTex = hpTex
        predBar._msufSelfHealPredAnchorRev = rev
    end
    if predBar.SetReverseFill then
        predBar:SetReverseFill(rev and true or false)
    end

    -- Incoming heals (self only)pass-through to StatusBar API.
    local inc = _MSUF_GetIncomingSelfHeals(unit)
    if type(inc) ~= "number" then
        inc = 0
    end
    if type(maxHP) == "number" then
        predBar:SetMinMaxValues(0, maxHP)
    else
        predBar:SetMinMaxValues(0, 1)
    end
    MSUF_SetBarValue(predBar, inc, false)
    predBar:Show()
end

-- Export for ns.Bars.ApplyHealthBars (remains in main file)
ns.Bars._UpdateSelfHealPrediction = _MSUF_UpdateSelfHealPrediction

-- ══════════════════════════════════════════════════════════════
-- Gradient system + Absorb bars + Reverse fill (was MSUF_Gradients.lua)
-- ══════════════════════════════════════════════════════════════

local function MSUF_HideTex(t)  if t then t:Hide() end  end
local _MSUF_GRAD_HIDE_KEYS = { "left", "right", "up", "down", "left2", "right2", "up2", "down2" }
local function MSUF_HideGradSet(grads, startIdx)
    if not grads then  return end
    for i = startIdx or 1, 8 do
        local t = grads[_MSUF_GRAD_HIDE_KEYS[i]]
        if t then t:Hide() end
    end
 end
local function MSUF_SetGrad(tex, orientation, a1, a2, strength)
    if not tex then  return end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha(orientation, 0, 0, 0, a1, 0, 0, 0, a2)
    elseif tex.SetGradient then
        tex:SetGradient(orientation, CreateColor(0, 0, 0, a1), CreateColor(0, 0, 0, a2))
    else
        tex:SetColorTexture(0, 0, 0, (a1 > a2) and a1 or a2)
    end
    if strength > 0 then tex:Show() else tex:Hide() end
 end
local function MSUF_ApplyBarGradient(frameOrTex, isPower)
    if not frameOrTex then  return end
    if not MSUF_DB then EnsureDB() end
    local g = MSUF_DB.general or {}
    local strength = g.gradientStrength or 0.45
    if isPower then
        if g.enablePowerGradient == false then strength = 0 end
    else
        if g.enableGradient == false then strength = 0 end
    end
    -- Allow applying to a standalone texture (used by some indicators).
    if frameOrTex.SetGradientAlpha and not (isPower and frameOrTex.powerGradients or frameOrTex.hpGradients) then
        local tex = frameOrTex
        local dir = g.gradientDirection
        if type(dir) ~= 'string' or dir == '' then dir = 'RIGHT'; g.gradientDirection = dir end
        local orientation, a1, a2 = 'HORIZONTAL', 0, strength
        if dir == 'LEFT' then a1, a2 = strength, 0
        elseif dir == 'UP' then orientation = 'VERTICAL'; a1, a2 = 0, strength
        elseif dir == 'DOWN' then orientation = 'VERTICAL'; a1, a2 = strength, 0 end
        MSUF_SetGrad(tex, orientation, a1, a2, strength)
         return
    end
    local frame = frameOrTex
    local bar = isPower and (frame.targetPowerBar or frame.powerBar) or frame.hpBar
    local grads = isPower and frame.powerGradients or frame.hpGradients
    if not bar or not grads then  return end
    -- Migrate old single-direction setting to the new per-edge toggles once.
    local hasNew = (g.gradientDirLeft ~= nil) or (g.gradientDirRight ~= nil) or (g.gradientDirUp ~= nil) or (g.gradientDirDown ~= nil)
    if not hasNew then
        local dir = g.gradientDirection
        if type(dir) ~= 'string' or dir == '' then dir = 'RIGHT' end
        dir = string.upper(dir)
        g.gradientDirLeft = (dir == 'LEFT')
        g.gradientDirRight = (dir == 'RIGHT')
        g.gradientDirUp = (dir == 'UP')
        g.gradientDirDown = (dir == 'DOWN')
    end
    local left = (g.gradientDirLeft == true)
    local right = (g.gradientDirRight == true)
    local up = (g.gradientDirUp == true)
    local down = (g.gradientDirDown == true)
    if not left and not right and not up and not down then right = true; g.gradientDirRight = true end
    if strength <= 0 then
        MSUF_HideGradSet(grads)
         return
    end
    if left then
        local useHalf = (right == true)
        local tex = grads.left
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('TOPLEFT', bar, 'TOPLEFT'); tex:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT'); tex:SetPoint('RIGHT', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'HORIZONTAL', strength, 0, strength)
        tex:Show()
    else MSUF_HideTex(grads.left) end
    if right then
        local useHalf = (left == true)
        local tex = grads.right
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('TOPRIGHT', bar, 'TOPRIGHT'); tex:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT'); tex:SetPoint('LEFT', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'HORIZONTAL', 0, strength, strength)
        tex:Show()
    else MSUF_HideTex(grads.right) end
    if up then
        local useHalf = (down == true)
        local tex = grads.up
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('TOPLEFT', bar, 'TOPLEFT'); tex:SetPoint('TOPRIGHT', bar, 'TOPRIGHT'); tex:SetPoint('BOTTOM', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'VERTICAL', 0, strength, strength)
        tex:Show()
    else MSUF_HideTex(grads.up) end
    if down then
        local useHalf = (up == true)
        local tex = grads.down
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT'); tex:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT'); tex:SetPoint('TOP', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'VERTICAL', strength, 0, strength)
        tex:Show()
    else MSUF_HideTex(grads.down) end
    MSUF_HideGradSet(grads, 5)
 end
local function MSUF_ApplyHPGradient(frameOrTex)  return MSUF_ApplyBarGradient(frameOrTex, false) end
local function MSUF_ApplyPowerGradient(frameOrTex)  return MSUF_ApplyBarGradient(frameOrTex, true) end
function _G.MSUF_ApplyPowerBarBorder(bar)
    if not bar then  return end
    local bdb = (MSUF_DB and MSUF_DB.bars) or nil
    local enabled = bdb and (bdb.powerBarBorderEnabled == true) or false
    local size = bdb and tonumber(bdb.powerBarBorderSize) or 1
    if type(size) ~= 'number' then size = 1 end
    if size < 1 then size = 1 elseif size > 10 then size = 10 end
    local border = bar._msufPowerBorder
    if not border then
        border = F.CreateFrame('Frame', nil, bar)
        border:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 2)
        border:EnableMouse(false)
        bar._msufPowerBorder = border
    end
    if not enabled then
        if border.Hide then border:Hide() end
         return
    end
    if border.SetBackdrop then
        border:SetBackdrop(nil)
    end
    border:ClearAllPoints()
    border:SetPoint('TOPLEFT', bar, 'TOPLEFT', 0, 0)
    border:SetPoint('TOPRIGHT', bar, 'TOPRIGHT', 0, 0)
    border:SetHeight(size)
    local line = border._msufSeparatorLine
    if not line and border.CreateTexture then
        line = border:CreateTexture(nil, 'OVERLAY')
        line:SetTexture('Interface\\Buttons\\WHITE8x8')
        line:SetVertexColor(0, 0, 0, 1)
        line:SetAllPoints(border)
        border._msufSeparatorLine = line
    elseif line and line.SetAllPoints then
        line:SetAllPoints(border)
    end
    border:Show()
 end
function _G.MSUF_ApplyPowerBarBorder_All()
    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= 'table' then  return end
    for _, f in pairs(frames) do
        local bar = f and (f.targetPowerBar or f.powerBar)
        if bar then
            _G.MSUF_ApplyPowerBarBorder(bar)
    end
    end
 end
local function MSUF_PreCreateHPGradients(hpBar)
    if not hpBar or not hpBar.CreateTexture then  return nil end
    local function MakeTex()
        local t = hpBar:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetBlendMode("BLEND")
        t:Hide()
         return t
    end
    return {
        left  = MakeTex(),
        right = MakeTex(),
        up    = MakeTex(),
        down  = MakeTex(),
    }
end
local function MSUF_UpdateAbsorbBars(self, unit, maxHP, isHeal)
    local bar = isHeal and self and self.healAbsorbBar or self and self.absorbBar
    local api = isHeal and UnitGetTotalHealAbsorbs or UnitGetTotalAbsorbs
    if not self or not bar or type(api) ~= 'function' then  return end
    local apply = _G.MSUF_ApplyAbsorbAnchorMode
    if type(apply) == 'function' then apply(self) end
    if isHeal then
        MSUF_ApplyHealAbsorbOverlayColor(bar)
    else
        if not MSUF_DB then EnsureDB() end
        MSUF_ApplyAbsorbOverlayColor(bar)
        local g = MSUF_DB.general or {}
        if g.enableAbsorbBar == false then
            MSUF_ResetBarZero(bar, true)
             return
    end
    end
    if _G.MSUF_AbsorbTextureTestMode then
        local max = maxHP or F.UnitHealthMax(unit) or 1
        bar:SetMinMaxValues(0, max)
        MSUF_SetBarValue(bar, max * (isHeal and 0.15 or 0.25))
        bar:Show()
         return
    end
    local total = api(unit)
    if not total then
        MSUF_ResetBarZero(bar, true)
         return
    end
    local max = maxHP or F.UnitHealthMax(unit) or 1
    bar:SetMinMaxValues(0, max)
    MSUF_SetBarValue(bar, total)
    bar:Show()
 end
local function MSUF_UpdateAbsorbBar(self, unit, maxHP)  return MSUF_UpdateAbsorbBars(self, unit, maxHP, false) end
local function MSUF_UpdateHealAbsorbBar(self, unit, maxHP)  return MSUF_UpdateAbsorbBars(self, unit, maxHP, true) end
    _G.MSUF_UpdateAbsorbBar = _G.MSUF_UpdateAbsorbBar or MSUF_UpdateAbsorbBar
    _G.MSUF_UpdateHealAbsorbBar = _G.MSUF_UpdateHealAbsorbBar or MSUF_UpdateHealAbsorbBar

    -- Absorb / Heal-Absorb anchoring modes
    -- 1/2: legacy (edge-anchored) with reverse-fill swap
    -- 3: follow current HP edge (Blizzard-style) by anchoring to the moving HP StatusBarTexture edge and clipping.
    -- NOTE: Mode 3 is secret-safe (no HP arithmetic) and reanchors only when mode/reverse-fill/width changes.
    local function MSUF_ApplyAbsorbAnchorMode(self)
        if not self then  return end

        if not MSUF_DB then EnsureDB() end
        local g = MSUF_DB and MSUF_DB.general or {}
        local mode = g.absorbAnchorMode or 2

        local hpBar = self.hpBar

        -- Restore legacy overlay layout (full overlay over hpBar).
        if mode ~= 3 then
            if self._msufAbsorbAnchorModeStamp == mode and not self._msufAbsorbFollowActive then
                return
            end

            self._msufAbsorbAnchorModeStamp = mode
            self._msufAbsorbFollowActive = nil
            self._msufAbsorbFollowRF = nil
            self._msufAbsorbFollowW = nil

            if self._msufAbsorbFollowClip and self._msufAbsorbFollowClip.Hide then
                self._msufAbsorbFollowClip:Hide()
            end

            local absorbReverse = (mode ~= 1)
            local healReverse   = not absorbReverse

            if self.absorbBar then
                if self.absorbBar.SetReverseFill then
                    self.absorbBar:SetReverseFill(absorbReverse and true or false)
                end
                if hpBar then
                    if self.absorbBar.GetParent and self.absorbBar:GetParent() ~= self then
                        self.absorbBar:SetParent(self)
                    end
                    self.absorbBar:ClearAllPoints()
                    self.absorbBar:SetAllPoints(hpBar)
                    if self.absorbBar.SetFrameLevel and hpBar.GetFrameLevel then
                        self.absorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 2)
                    end
                end
            end

            if self.healAbsorbBar then
                if self.healAbsorbBar.SetReverseFill then
                    self.healAbsorbBar:SetReverseFill(healReverse and true or false)
                end
                if hpBar then
                    if self.healAbsorbBar.GetParent and self.healAbsorbBar:GetParent() ~= self then
                        self.healAbsorbBar:SetParent(self)
                    end
                    self.healAbsorbBar:ClearAllPoints()
                    self.healAbsorbBar:SetAllPoints(hpBar)
                    if self.healAbsorbBar.SetFrameLevel and hpBar.GetFrameLevel then
                        self.healAbsorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 3)
                    end
                end
            end

            return
        end

        -- Mode 3: follow current HP edge.
        if not hpBar or not hpBar.GetStatusBarTexture then
            return
        end

        local hpTex = hpBar:GetStatusBarTexture()
        if not hpTex then
            return
        end

        local hpReverse = false
        if hpBar.GetReverseFill then
            local ok, rf = pcall(hpBar.GetReverseFill, hpBar)
            if ok and rf then
                hpReverse = true
            end
        end

        local w = nil
        if hpBar.GetWidth then
            w = hpBar:GetWidth()
        end

        if self._msufAbsorbAnchorModeStamp == 3 and self._msufAbsorbFollowActive
            and self._msufAbsorbFollowRF == hpReverse and self._msufAbsorbFollowW == w then
            return
        end

        self._msufAbsorbAnchorModeStamp = 3
        self._msufAbsorbFollowActive = true
        self._msufAbsorbFollowRF = hpReverse
        self._msufAbsorbFollowW = w

        local clip = self._msufAbsorbFollowClip
        if not clip and _G.CreateFrame and hpBar then
            clip = _G.CreateFrame("Frame", nil, hpBar)
            clip:SetAllPoints(hpBar)
            if clip.SetClipsChildren then
                clip:SetClipsChildren(true)
            end
            self._msufAbsorbFollowClip = clip
        elseif clip then
            clip:ClearAllPoints()
            clip:SetAllPoints(hpBar)
        end
        if clip and clip.SetFrameLevel and hpBar.GetFrameLevel then
            clip:SetFrameLevel(hpBar:GetFrameLevel() + 2)
        end
        if clip and clip.Show then
            clip:Show()
        end

        -- Absorb: outward (same direction as HP). Heal-Absorb: inward (opposite direction).
        if self.absorbBar then
            if clip and self.absorbBar.GetParent and self.absorbBar:GetParent() ~= clip then
                self.absorbBar:SetParent(clip)
            end
            self.absorbBar:ClearAllPoints()
            if hpReverse then
                self.absorbBar:SetPoint("TOPRIGHT", hpTex, "TOPLEFT", 0, 0)
                self.absorbBar:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMLEFT", 0, 0)
                if self.absorbBar.SetReverseFill then
                    self.absorbBar:SetReverseFill(true)
                end
            else
                self.absorbBar:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", 0, 0)
                self.absorbBar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)
                if self.absorbBar.SetReverseFill then
                    self.absorbBar:SetReverseFill(false)
                end
            end
            if type(w) == "number" and w > 0 and self.absorbBar.SetWidth then
                if self.absorbBar._msufFollowW ~= w then
                    self.absorbBar:SetWidth(w)
                    self.absorbBar._msufFollowW = w
                end
            end
            if self.absorbBar.SetFrameLevel and hpBar.GetFrameLevel then
                self.absorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 2)
            end
        end

        if self.healAbsorbBar then
            if clip and self.healAbsorbBar.GetParent and self.healAbsorbBar:GetParent() ~= clip then
                self.healAbsorbBar:SetParent(clip)
            end
            self.healAbsorbBar:ClearAllPoints()
            if hpReverse then
                -- inward: extend right into HP
                self.healAbsorbBar:SetPoint("TOPLEFT", hpTex, "TOPLEFT", 0, 0)
                self.healAbsorbBar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
                if self.healAbsorbBar.SetReverseFill then
                    self.healAbsorbBar:SetReverseFill(false)
                end
            else
                -- inward: extend left into HP
                self.healAbsorbBar:SetPoint("TOPRIGHT", hpTex, "TOPRIGHT", 0, 0)
                self.healAbsorbBar:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
                if self.healAbsorbBar.SetReverseFill then
                    self.healAbsorbBar:SetReverseFill(true)
                end
            end
            if type(w) == "number" and w > 0 and self.healAbsorbBar.SetWidth then
                if self.healAbsorbBar._msufFollowW ~= w then
                    self.healAbsorbBar:SetWidth(w)
                    self.healAbsorbBar._msufFollowW = w
                end
            end
            if self.healAbsorbBar.SetFrameLevel and hpBar.GetFrameLevel then
                self.healAbsorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 3)
            end
        end
     end
_G.MSUF_ApplyAbsorbAnchorMode = MSUF_ApplyAbsorbAnchorMode
-- Per-unit reverse fill for HP/Power bars.
-- If Absorb Anchoring is set to "Follow current HP", this also re-syncs absorb/heal-absorb overlays.
local function MSUF_ApplyReverseFillBars(self, conf)
    if not self then  return end
    local rf = (conf and conf.reverseFillBars == true) or false
    if self._msufReverseFillBarsStamp == rf then
         return
    end
    self._msufReverseFillBarsStamp = rf
    if self.hpBar and self.hpBar.SetReverseFill then
        self.hpBar:SetReverseFill(rf and true or false)
    end
    if self.selfHealPredBar and self.selfHealPredBar.SetReverseFill then
        self.selfHealPredBar:SetReverseFill(rf and true or false)
    end
    local p = self.targetPowerBar or self.powerBar
    if p and p.SetReverseFill then
        p:SetReverseFill(rf and true or false)
    end

    -- Keep absorb/heal-absorb follow-HP anchoring in sync with reverse-fill changes.
    local g = MSUF_DB and MSUF_DB.general
    if g and g.absorbAnchorMode == 3 then
        local apply = _G.MSUF_ApplyAbsorbAnchorMode
        if apply then
            apply(self)
        end
    end
 end
_G.MSUF_ApplyReverseFillBars = _G.MSUF_ApplyReverseFillBars or MSUF_ApplyReverseFillBars

-- Exports for main file callers
ns.Bars._ApplyHPGradient = MSUF_ApplyHPGradient
ns.Bars._ApplyPowerGradient = MSUF_ApplyPowerGradient
ns.Bars._PreCreateHPGradients = MSUF_PreCreateHPGradients
ns.Bars._UpdateAbsorbBar = MSUF_UpdateAbsorbBar
ns.Bars._UpdateHealAbsorbBar = MSUF_UpdateHealAbsorbBar
ns.Bars._ApplyReverseFillBars = MSUF_ApplyReverseFillBars
