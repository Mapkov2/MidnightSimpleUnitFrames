-- Castbars/MSUF_CastbarPreviews.lua
-- Phase 2 extraction: All preview, test mode, and edit mode functions.
-- Zero combat path — only used in MSUF Edit Mode.

local _EnsureDBLazy = _G.MSUF_EnsureDBLazy or function()
    if not MSUF_DB and type(EnsureDB) == "function" then EnsureDB() end
end

-- NOTE: Core stores the unitframe table on _G.MSUF_UnitFrames (not a global "UnitFrames").
-- The LoD module must anchor Edit Mode previews against that table, otherwise previews
-- can appear missing (unanchored/off-screen).
local UnitFrames = _G.MSUF_UnitFrames

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

-- =====================================================================
-- Cluster B+E: Shared parametric TestMode for simple castbar previews.
-- Target and Focus are structurally identical; only config keys differ.
-- cfg = {
--   dbKey       = "targetCastbarTestMode",
--   flagKey     = "MSUF_targetTestMode",
--   previewName = "MSUF_TargetCastbarPreview",
--   reanchorFn  = "MSUF_ReanchorTargetCastBar",
--   showTimeKey = "showTargetCastTime",
--   label       = "Target castbar preview",
-- }
-- =====================================================================

-- Cluster E: Shared OnUpdate for simple preview dummy casts (Target, Focus).
local function _MSUF_SimplePreview_OnUpdate(self)
    if not self or not self._msufTestActive then return end

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
        local showTime = self._msufTestShowTime
        if showTime then
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
end

local function _MSUF_SetSimpleCastbarTestMode(cfg, active, keepSetting)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local want
    if keepSetting then
        want = active and true or false
    else
        g[cfg.dbKey] = active and true or false
        want = g[cfg.dbKey] and true or false
    end

    if not MSUF_UnitEditModeActive then
        want = false
    end

    local fPrev = _G[cfg.previewName]
    local f = (fPrev and fPrev.statusBar) and fPrev or nil
    if not f or not f.statusBar then return end

    -- Ensure time text exists on the preview.
    if not f.timeText and f.statusBar and f.statusBar.CreateFontString then
        f.timeText = f.statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.timeText:SetPoint("RIGHT", f.statusBar, "RIGHT", -4, 0)
        f.timeText:SetJustifyH("RIGHT")
    end

    if not want then
        if f._msufTestActive then
            f._msufTestActive = nil
            f._msufTestShowTime = nil
            f[cfg.flagKey] = nil
            f:SetScript("OnUpdate", nil)
            if f.statusBar and f.statusBar.SetMinMaxValues then
                f.statusBar:SetMinMaxValues(0, 1)
                f.statusBar:SetValue(0.5)
            end
            if f.castText and f.castText.SetText then
                f.castText:SetText(cfg.label)
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
    f._msufTestActive = true
    f[cfg.flagKey] = true

    local reanchorFn = _G[cfg.reanchorFn]
    if type(reanchorFn) == "function" then reanchorFn() end
    if MSUF_UpdateCastbarVisuals then MSUF_UpdateCastbarVisuals() end

    if f.castText and f.castText.SetText then
        f.castText:SetText("Test Cast")
        f.castText:Show()
        f.castText:SetAlpha(1)
    end

    if f.icon and f.icon.SetTexture then
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if f.icon.Show then f.icon:Show() end
    end

    local showTime = (g[cfg.showTimeKey] ~= false)
    f._msufTestShowTime = showTime
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

    f:SetScript("OnUpdate", _MSUF_SimplePreview_OnUpdate)
end

-- Target castbar test mode (thin wrapper).
function _G.MSUF_SetTargetCastbarTestMode(active, keepSetting)
    _MSUF_SetSimpleCastbarTestMode({
        dbKey       = "targetCastbarTestMode",
        flagKey     = "MSUF_targetTestMode",
        previewName = "MSUF_TargetCastbarPreview",
        reanchorFn  = "MSUF_ReanchorTargetCastBar",
        showTimeKey = "showTargetCastTime",
        label       = "Target castbar preview",
    }, active, keepSetting)
end

-- Focus castbar test mode (thin wrapper).
function _G.MSUF_SetFocusCastbarTestMode(active, keepSetting)
    _MSUF_SetSimpleCastbarTestMode({
        dbKey       = "focusCastbarTestMode",
        flagKey     = "MSUF_focusTestMode",
        previewName = "MSUF_FocusCastbarPreview",
        reanchorFn  = "MSUF_ReanchorFocusCastBar",
        showTimeKey = "showFocusCastTime",
        label       = "Focus castbar preview",
    }, active, keepSetting)
end

-- Boss castbar: looping dummy cast on the BOSS castbar preview while the boss castbar popup is open.
-- We do NOT override bar colors here; MSUF_UpdateBossCastbarPreview applies the user's configured colors.
-- Cluster E: Named OnUpdate for Boss preview dummy casts (avoids per-frame closure allocation).
local function _MSUF_BossPreview_OnUpdate(self)
    if not self or not self.MSUF_bossTestMode then return end

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
            if t.GetAlpha then a = t:GetAlpha() or 0 end
            if a < 0.9 then t:SetAlpha(1) end
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
        if self._msufTestShowTime then
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
end

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
        f._msufTestShowTime = showTime
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

        f:SetScript("OnUpdate", _MSUF_BossPreview_OnUpdate)
    end)
end

-- ============================================================
-- Player castbar icon layout helper (prevents "reserved black gap")
-- Detach only when IconOffsetX ~= 0 (Y is cosmetic)
-- NOTE: Player castbar icon is positionable via Edit Mode, but visibility respects the player Icon toggle
--       (except while in Edit Mode, where we keep it visible so it can be repositioned).
-- ============================================================

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




local function MSUF_CreatePlayerCastbarPreview()
    -- Real implementation (no recursion). Creates the MSUF Edit Mode preview for the player castbar.
    if _G.MSUF_PlayerCastbarPreview then
        MSUF_PlayerCastbarPreview = _G.MSUF_PlayerCastbarPreview
        return MSUF_PlayerCastbarPreview
    end

    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}

    local w = tonumber(g.castbarPlayerBarWidth) or tonumber(g.castbarGlobalWidth) or 250
    local h = tonumber(g.castbarPlayerBarHeight) or tonumber(g.castbarGlobalHeight) or 18

    local f = MSUF_CreateCastbarPreviewFrame("player", "MSUF_PlayerCastbarPreview", {
        parent = UIParent,
        strata = "DIALOG",
        width  = w,
        height = h,
        label  = "Player castbar preview",
        showIcon = true,
        showTime = true,
        bgAlpha = 0.8,
        initialValue = 0.5,
    })
    if not f then return end

    _G.MSUF_PlayerCastbarPreview = f
    MSUF_PlayerCastbarPreview = f

    MSUF_SetupCastbarPreviewEditHandlers(f, "player")

    -- Apply visuals once so the preview matches current settings.
    if type(MSUF_UpdateCastbarVisuals) == "function" then
        MSUF_UpdateCastbarVisuals()
    end
    if type(MSUF_UpdateCastbarTextures) == "function" then
        MSUF_UpdateCastbarTextures()
    end

    if type(MSUF_PositionPlayerCastbarPreview) == "function" then
        MSUF_PositionPlayerCastbarPreview()
    end

    return f
end


local function MSUF_CreateTargetCastbarPreview()
    -- Real implementation (no recursion). Creates the MSUF Edit Mode preview for the target castbar.
    if _G.MSUF_TargetCastbarPreview then
        MSUF_TargetCastbarPreview = _G.MSUF_TargetCastbarPreview
        return MSUF_TargetCastbarPreview
    end

    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}

    local w = tonumber(g.castbarTargetBarWidth) or tonumber(g.castbarGlobalWidth) or 250
    local h = tonumber(g.castbarTargetBarHeight) or tonumber(g.castbarGlobalHeight) or 18

    local f = MSUF_CreateCastbarPreviewFrame("target", "MSUF_TargetCastbarPreview", {
        parent = UIParent,
        strata = "DIALOG",
        width  = w,
        height = h,
        label  = "Target castbar preview",
        showIcon = true,
        showTime = true,
        bgAlpha = 0.8,
        initialValue = 0.5,
    })
    if not f then return end

    _G.MSUF_TargetCastbarPreview = f
    MSUF_TargetCastbarPreview = f

    MSUF_SetupCastbarPreviewEditHandlers(f, "target")

    if type(MSUF_UpdateCastbarVisuals) == "function" then
        MSUF_UpdateCastbarVisuals()
    end
    if type(MSUF_UpdateCastbarTextures) == "function" then
        MSUF_UpdateCastbarTextures()
    end

    if type(MSUF_PositionTargetCastbarPreview) == "function" then
        MSUF_PositionTargetCastbarPreview()
    end

    return f
end

local function MSUF_CreateFocusCastbarPreview()
    -- Real implementation (no recursion). Creates the MSUF Edit Mode preview for the focus castbar.
    if _G.MSUF_FocusCastbarPreview then
        MSUF_FocusCastbarPreview = _G.MSUF_FocusCastbarPreview
        return MSUF_FocusCastbarPreview
    end

    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}

    local w = tonumber(g.castbarFocusBarWidth) or tonumber(g.castbarGlobalWidth) or 250
    local h = tonumber(g.castbarFocusBarHeight) or tonumber(g.castbarGlobalHeight) or 18

    local f = MSUF_CreateCastbarPreviewFrame("focus", "MSUF_FocusCastbarPreview", {
        parent = UIParent,
        strata = "DIALOG",
        width  = w,
        height = h,
        label  = "Focus castbar preview",
        showIcon = true,
        showTime = true,
        bgAlpha = 0.8,
        initialValue = 0.5,
    })
    if not f then return end

    _G.MSUF_FocusCastbarPreview = f
    MSUF_FocusCastbarPreview = f

    MSUF_SetupCastbarPreviewEditHandlers(f, "focus")

    if type(MSUF_UpdateCastbarVisuals) == "function" then
        MSUF_UpdateCastbarVisuals()
    end
    if type(MSUF_UpdateCastbarTextures) == "function" then
        MSUF_UpdateCastbarTextures()
    end

    if type(MSUF_PositionFocusCastbarPreview) == "function" then
        MSUF_PositionFocusCastbarPreview()
    end

    return f
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

    -- Core owns the unitframe table; refresh our reference (safe, edit-mode only).
    UnitFrames = UnitFrames or _G.MSUF_UnitFrames

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

    UnitFrames = UnitFrames or _G.MSUF_UnitFrames

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

    UnitFrames = UnitFrames or _G.MSUF_UnitFrames

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

    UnitFrames = UnitFrames or _G.MSUF_UnitFrames

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

---------------------------------------------------------------------------
-- _G exports (most TestMode functions already defined directly on _G)
---------------------------------------------------------------------------
_G.MSUF_HideBlizzardPlayerCastbar      = MSUF_HideBlizzardPlayerCastbar
_G.MSUF_SyncBossCastbarSliders         = MSUF_SyncBossCastbarSliders
if type(_G.MSUF_CreatePlayerCastbarPreview) ~= 'function' then _G.MSUF_CreatePlayerCastbarPreview = MSUF_CreatePlayerCastbarPreview end
if type(_G.MSUF_CreateTargetCastbarPreview) ~= 'function' then _G.MSUF_CreateTargetCastbarPreview = MSUF_CreateTargetCastbarPreview end
if type(_G.MSUF_CreateFocusCastbarPreview) ~= 'function' then _G.MSUF_CreateFocusCastbarPreview = MSUF_CreateFocusCastbarPreview end
_G.MSUF_PositionPlayerCastbarPreview   = MSUF_PositionPlayerCastbarPreview
_G.MSUF_PositionTargetCastbarPreview   = MSUF_PositionTargetCastbarPreview
_G.MSUF_PositionFocusCastbarPreview    = MSUF_PositionFocusCastbarPreview
_G.MSUF_UpdatePlayerCastbarPreview     = MSUF_UpdatePlayerCastbarPreview
