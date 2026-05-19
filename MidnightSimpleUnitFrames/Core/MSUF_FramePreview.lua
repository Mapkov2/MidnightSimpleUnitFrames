-- MSUF_FramePreview.lua
-- Edit-mode unitframe preview rendering. Split from MidnightSimpleUnitFrames.lua
-- because preview fake data, placeholder bars, and no-unit visuals are separate
-- from secure frame creation and normal runtime updates.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}

local type, tonumber, tostring, select = type, tonumber, tostring, select
local InCombatLockdown = InCombatLockdown
local F = (ns.Cache and ns.Cache.F) or {}

local function FramePreview_ResetBarZero(bar, hide)
    if not bar then return false end
    if bar.SetMinMaxValues then bar:SetMinMaxValues(0, 1) end
    if bar.SetValue then bar:SetValue(0) end
    bar.MSUF_lastValue = 0
    if hide and bar.Hide then bar:Hide() end
    return true
end

local function FramePreview_ClearText(fs, hide)
    if fs and fs.SetText then fs:SetText("") end
    if hide and fs and fs.Hide then fs:Hide() end
end

local function FramePreview_ClearUnitFrameState(self, clearAbsorbs)
    if ns.Bars and ns.Bars.ResetHealthAndOverlays then
        ns.Bars.ResetHealthAndOverlays(self, clearAbsorbs)
    end
    if self.nameText then self.nameText:SetText("") end
    FramePreview_ClearText(self.raidGroupNameText, true)
    FramePreview_ClearText(self.levelText, true)
    FramePreview_ClearText(self.hpTextLeft, true)
    FramePreview_ClearText(self.hpTextCenter, true)
    FramePreview_ClearText(self.hpText, true)
    if ns.Text and ns.Text.ClearField then ns.Text.ClearField(self, "hpTextPct") end
    FramePreview_ClearText(self.powerTextLeft, true)
    FramePreview_ClearText(self.powerTextCenter, true)
    FramePreview_ClearText(self.powerText, true)
    if ns.Text and ns.Text.ClearField then ns.Text.ClearField(self, "powerTextPct") end
end

local function FramePreview_RaidGroupNameAllowedForKey(key)
    local fn = _G.MSUF_RaidGroupNameAllowedForKey
    if type(fn) == "function" then return fn(key) end
    return key == "player" or key == "target" or key == "focus" or key == "pet"
end

local function FramePreview_RaidGroupNamePreviewText(conf)
    local fn = _G.MSUF_RaidGroupNamePreviewText
    if type(fn) == "function" then return fn(conf) end
    return "G1"
end
-- Edit Mode unitframe preview:
-- When a unitframe has no unit (or is disabled) we still want a persistent, simple preview
-- so it can be positioned/edited. This is intentionally a "dark bar" placeholder and
-- must never run in combat.
local function MSUF_ApplyUnitframePreviewOverlays(self, unit, maxHP)
    if not (self and self.hpBar) then return end
    maxHP = tonumber(maxHP) or 100
    if maxHP <= 0 then maxHP = 100 end

    local healPredEnabled = ns.Bars._IsHealPredictionEnabled and ns.Bars._IsHealPredictionEnabled()
    if healPredEnabled and type(ns.Bars._SetSelfHealPredictionTestValue) == "function" then
        ns.Bars._SetSelfHealPredictionTestValue(self, maxHP, maxHP * 0.18)
    elseif type(ns.Bars._HideSelfHealPrediction) == "function" then
        ns.Bars._HideSelfHealPrediction(self)
    end

    local absorbEnabled = true
    if type(ns.Bars._ResolveAbsorbDisplay) == "function" then
        absorbEnabled = ns.Bars._ResolveAbsorbDisplay(unit or self.unit)
    end
    if self.absorbBar then
        if absorbEnabled then
            local applyAnchor = _G.MSUF_ApplyAbsorbAnchorMode
            if type(applyAnchor) == "function" then applyAnchor(self) end
            if type(ns.Bars._ApplyAbsorbOverlayColor) == "function" then
                ns.Bars._ApplyAbsorbOverlayColor(self.absorbBar, unit or self.unit)
            end
            self.absorbBar:SetMinMaxValues(0, maxHP)
            self.absorbBar:SetValue(maxHP * 0.25)
            if self.absorbBar.Show then self.absorbBar:Show() end
        else
            FramePreview_ResetBarZero(self.absorbBar, true)
        end
    end
    if self.healAbsorbBar then
        FramePreview_ResetBarZero(self.healAbsorbBar, true)
    end
end

local function MSUF_ApplyUnitframeEditPreview(self, key, conf, g)
    if not self or self.isBoss then return end
    if _G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()) then return end
    if not MSUF_DB then MSUF_EnsureDB() end
    g = g or ((MSUF_DB and MSUF_DB.general) or {})

    if self.Show then self:Show() end
    if _G.MSUF_ApplyUnitAlpha then
        _G.MSUF_ApplyUnitAlpha(self, key or self.unit)
    end

    -- Clear any sticky state from previously shown units.
    FramePreview_ClearUnitFrameState(self, true)

    if self.portrait and self.portrait.Hide then self.portrait:Hide() end

    -- Use stable, constant fake values so text/offsets can be edited visually.
    -- (No secret-value interaction, no unit API reads.)
    local fakeHp = 0.73
    local fakePower = 0.52

    local hb = self.hpBar
    if hb then
        MSUF_SetBarMinMax(hb, 0, 1)
        hb:SetValue(fakeHp)

        -- Use the configured dark tone (defaults to black) for a consistent placeholder.
        local darkR, darkG, darkB = 0, 0, 0
        local _gray = g.darkBarGray
        if type(_gray) == "number" then
            if _gray < 0 then _gray = 0 elseif _gray > 1 then _gray = 1 end
            darkR, darkG, darkB = _gray, _gray, _gray
        else
            local toneKey = g.darkBarTone or "black"
            local tone = MSUF_DARK_TONES and MSUF_DARK_TONES[toneKey]
            if tone then
                darkR, darkG, darkB = tone[1] or 0, tone[2] or 0, tone[3] or 0
            end
        end
        if hb.SetStatusBarColor then hb:SetStatusBarColor(darkR, darkG, darkB, 1) end
        if self.bg then
            MSUF_ApplyBarBackgroundVisual(self)
        end
        if self.hpGradients then
            ns.Bars._ApplyHPGradient(self)
        elseif self.hpGradient then
            ns.Bars._ApplyHPGradient(self.hpGradient)
        end
    end
    MSUF_ApplyUnitframePreviewOverlays(self, key or self.unit, 1)

    -- Show a fake power bar + fake power text so offsets can be edited.
    local pb = self.targetPowerBar or self.powerBar
    if pb then
        if pb.Show then pb:Show() end
        MSUF_SetBarMinMax(pb, 0, 1)
        pb:SetValue(fakePower)
        if pb.SetStatusBarColor then
            -- Simple, readable "mana-like" placeholder.
            pb:SetStatusBarColor(0.20, 0.60, 1.00, 1)
        end
        -- If the bar has its own background texture, keep it visible.
        if pb.bg and pb.bg.Show then pb.bg:Show() end
    end

    -- If both a "main" powerBar and a "targetPowerBar" exist, make sure only one is shown.
    if self.targetPowerBar and self.powerBar and self.powerBar ~= self.targetPowerBar then
        if pb == self.targetPowerBar then
            if self.powerBar.Hide then self.powerBar:Hide() end
        else
            if self.targetPowerBar.Hide then self.targetPowerBar:Hide() end
        end
    end

    local SetShown = (ns and ns.Util and ns.Util.SetShown) or nil

    -- Placeholder label (safe constant).
    local label = key or self.unit or "unit"
    if label == "targettarget" then label = "ToT" end
    if type(label) ~= "string" then label = tostring(label) end
    local upper = (string and string.upper and string.upper(label)) or label

    if self.nameText and self.nameText.SetText then
        if type(MSUF_SetTextIfChanged) == "function" then
            MSUF_SetTextIfChanged(self.nameText, upper)
        else
            self.nameText:SetText(upper)
        end
        if SetShown then SetShown(self.nameText, true) end
    end
    if self.raidGroupNameText and self.raidGroupNameText.SetText then
        local showRG = (conf and conf.showRaidGroupInName == true) and FramePreview_RaidGroupNameAllowedForKey(key or self.msufConfigKey or self.unit)
        if showRG then
            local rgText = FramePreview_RaidGroupNamePreviewText(conf)
            if type(MSUF_SetTextIfChanged) == "function" then
                MSUF_SetTextIfChanged(self.raidGroupNameText, rgText)
            else
                self.raidGroupNameText:SetText(rgText)
            end
        else
            if type(MSUF_SetTextIfChanged) == "function" then
                MSUF_SetTextIfChanged(self.raidGroupNameText, "")
            else
                self.raidGroupNameText:SetText("")
            end
        end
        if SetShown then SetShown(self.raidGroupNameText, showRG) end
        if _G.MSUF_ApplyRaidGroupNameLayout then _G.MSUF_ApplyRaidGroupNameLayout(self) end
    end

    if self.hpText and self.hpText.SetText then
        -- Fake HP text (constant) so users can position/size text reliably.
        if type(MSUF_SetTextIfChanged) == "function" then
            MSUF_SetTextIfChanged(self.hpText, "73% 123.4k")
        else
            self.hpText:SetText("73% 123.4k")
        end
        if SetShown then SetShown(self.hpText, true) end
    end

    if self.powerText and self.powerText.SetText then
        -- Fake power text for edit positioning.
        if type(MSUF_SetTextIfChanged) == "function" then
            MSUF_SetTextIfChanged(self.powerText, "52% 65")
        else
            self.powerText:SetText("52% 65")
        end
        if SetShown then SetShown(self.powerText, true) end
    end

    if self.levelText and self.levelText.SetText then
        -- Show a stable fake level value.
        if type(MSUF_SetTextIfChanged) == "function" then
            MSUF_SetTextIfChanged(self.levelText, "70")
        else
            self.levelText:SetText("70")
        end
        if SetShown then SetShown(self.levelText, true) end
    end

    -- Portrait preview (2D placeholder + Class Icon mode)
    if self.portrait and conf then
        local pm = conf.portraitMode or "OFF"
        if pm ~= "OFF" then
            if _G.MSUF_UpdateBossPortraitLayout then
                _G.MSUF_UpdateBossPortraitLayout(self, conf)
            end

            local pr = (conf.portraitRender == "CLASS") and "CLASS" or "2D"
            if pr == "CLASS" then
                local class = (F.UnitClassBase and F.UnitClassBase("player")) or (F.UnitClass and select(2, F.UnitClass("player")))
                local coords = (class and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[class]) or nil
                if coords and self.portrait.SetTexture and self.portrait.SetTexCoord then
                    self.portrait:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                    self.portrait:SetTexCoord(coords[1] or 0, coords[2] or 1, coords[3] or 0, coords[4] or 1)
                elseif self.portrait.SetTexture then
                    self.portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                    if self.portrait.SetTexCoord then
                        self.portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                    end
                end
            else
                -- Placeholder portrait (question mark) so the portrait position/size can be edited.
                if self.portrait.SetTexture then
                    self.portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                end
                if self.portrait.SetTexCoord then
                    self.portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                end
            end

            if self.portrait.Show then self.portrait:Show() end
        else
            if self.portrait.Hide then self.portrait:Hide() end
        end
    end

    ns.UF.HideLeaderAndRaidMarker(self)
    self._msufNoUnitCleared = nil
end
_G.MSUF_ApplyUnitframePreviewOverlays = MSUF_ApplyUnitframePreviewOverlays
_G.MSUF_ApplyUnitframeEditPreview = MSUF_ApplyUnitframeEditPreview
