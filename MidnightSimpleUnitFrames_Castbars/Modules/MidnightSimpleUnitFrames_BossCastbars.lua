-- MidnightSimpleUnitFrames - Boss Castbar Module (bootstrap)
-- Step 0: Show MSUF-style boss castbars (boss1..boss5) without options UI.
-- Goals for Step 0:
--   - Use the SAME interruptible/non-interruptible color sources as MSUF (so the Colors menu applies automatically).
--   - Use MSUF's castbar layout (icon is OUTSIDE the statusbar fill area; no overlap).
--   - Use duration-objects (UnitCastingDuration/UnitChannelDuration) + MSUF_CastbarManager if available.

local addonName, ns = ...
ns = ns or {}

local MAX_BOSS = _G.MSUF_MAX_BOSS_FRAMES or 5

-- Forward declarations
local BossCastbar_Start
local BossCastbar_Stop

-- Keep boss interrupt feedback duration consistent with the core castbar driver (Target/Focus/etc).
-- IMPORTANT: This is NOT the end-of-cast hide grace. This is the "Interrupted" feedback hold time.
-- The castbar driver already defines `_G.MSUF_INTERRUPT_FEEDBACK_DURATION` (default 0.5s).
-- Boss uses that same value so all units feel identical.
local MSUF_BOSS_INTERRUPT_FEEDBACK_DURATION = 0.5

local function MSUF_GetInterruptFeedbackGrace()
    -- Preferred global: shared with the main castbar driver.
    local g = _G.MSUF_INTERRUPT_FEEDBACK_DURATION
    if type(g) == "number" and g > 0 then
        return g
    end

    -- Legacy alias (older patches used this name).
    g = _G.MSUF_INTERRUPT_FEEDBACK_GRACE
    if type(g) == "number" and g > 0 then
        return g
    end

    return MSUF_BOSS_INTERRUPT_FEEDBACK_DURATION
end

-- -------------------------------------------------
-- Safe helpers
-- -------------------------------------------------
local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = MSUF_FastCall(fn, ...)
    if ok then return a, b, c, d, e end
    return nil
end

-- PERF FIX: Resolve the best clock function once at load time instead of type-checking every call.
local MSUF_Now
if type(_G.GetTimePreciseSec) == "function" then
    MSUF_Now = _G.GetTimePreciseSec
elseif type(_G.GetTime) == "function" then
    MSUF_Now = _G.GetTime
else
    MSUF_Now = function() return 0 end
end

-- Canonical-unit helper for boss castbars: when a boss is also your target/focus,
-- use that unit token for duration objects so Boss and Target/Focus stay frame-perfect in sync.
-- We only use it for Unit*Duration calls (timer driving), never for identity/visibility decisions.
local function MSUF_GetCanonicalCastUnitForBoss(unit)
    -- IMPORTANT: Never compare GUIDs here (UnitGUID can be secret-wrapped in Midnight and
    -- any comparison/stringification can throw "attempt to compare a secret value").
    -- We only need a canonical unit token for duration/timer-driving.
    if type(unit) ~= "string" or not unit:match("^boss%d") then
        return unit
    end

    -- UnitIsUnit is the safe way to test identity across unit tokens.
    if type(_G.UnitIsUnit) == "function" then
        if _G.UnitIsUnit(unit, "target") then
            return "target"
        end
        if _G.UnitIsUnit(unit, "focus") then
            return "focus"
        end
    end

    return unit
end


-- Secret-safe number coercion: returns a plain Lua number or nil if the value is a secret.
-- PERF FIX: Use a pre-allocated function instead of creating a new closure on every call.
local function _bossSecretAdd(v) return v + 0 end
local function ToPlainNumber(v)
    if v == nil then return nil end
    if type(v) == "number" then return v end
    local ok, n = pcall(_bossSecretAdd, v)
    if ok and type(n) == "number" then
        return n
    end
    return nil
end

-- ------------------------------------------------------------
-- Empower support (make boss empower castbars look like player)
-- ------------------------------------------------------------

-- Clear empower visuals/state (mirrors the core castbar driver behavior)
local function Boss_ClearEmpowerState(frame)
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

-- Best-effort empower timeline builder for a unit token.
-- Returns nil if this unit is not currently using an empower cast.
local function Boss_BuildEmpowerTimeline(unit, startTimeMS, endTimeMS)
    -- Empower is player-only in MSUF Castbars (Midnight/Beta secret-safe).
    -- Boss/Target/Focus empower stage APIs are unreliable and may return secret values.
    -- We intentionally disable empower timeline building for bosses and fall back to normal cast/channel handling.
    return nil
end

local function GetColorFromKeyFallback(key)
    if key == "red" then return 1, 0, 0 end
    if key == "green" then return 0, 1, 0 end
    if key == "blue" then return 0, 0.5, 1 end
    if key == "white" then return 1, 1, 1 end
    if key == "yellow" then return 1, 0.9, 0.1 end
    if key == "turquoise" then return 0.2, 0.8, 0.8 end
    return 0.85, 0.2, 0.2
end

-- PERF FIX: EnsureDB only needs to run once; after MSUF_DB exists it's a no-op.
local _bossDBReady = false
local function EnsureDBSafe()
    if _bossDBReady then return end
    if type(_G.EnsureDB) == "function" then
        SafeCall(_G.EnsureDB)
    end
    if _G.MSUF_DB then _bossDBReady = true end
end

-- ------------------------------------------------------------
-- Global font pack helper (keeps boss castbars in sync with Colors menu)
-- ------------------------------------------------------------
local function MSUF_GetGlobalFontPack_Boss()
    local path, flags, r, g, b, baseSize, useShadow
    if type(_G.MSUF_GetGlobalFontSettings) == "function" then
        path, flags, r, g, b, baseSize, useShadow = _G.MSUF_GetGlobalFontSettings()
    end
    if not path or path == "" then path = "Fonts\\FRIZQT__.TTF" end
    if not flags or flags == "" then flags = "OUTLINE" end
    r = (r ~= nil) and r or 1
    g = (g ~= nil) and g or 1
    b = (b ~= nil) and b or 1
    baseSize = tonumber(baseSize) or 12
    useShadow = useShadow and true or false
    return path, flags, r, g, b, baseSize, useShadow
end


local function IsBossCastbarEnabled()
    EnsureDBSafe()
    local db = _G.MSUF_DB
    local g = db and db.general
    return (not g) or (g.enableBossCastbar ~= false)
end



local function ApplyBossCastbarTimeSetting()
    EnsureDBSafe()
    local db = _G.MSUF_DB
    local g = db and db.general
    local showTime = (not g) or (g.showBossCastTime ~= false)

    local frames = _G.MSUF_BossCastbars
    if not frames then return end

    for i = 1, #frames do
        local f = frames[i]
        if f and f.timeText then
            -- Keep shown; toggle via alpha to avoid layout side-effects.
            f.timeText:Show()
            f.timeText:SetAlpha(showTime and 1 or 0)
        end
    end
-- Keep Castbar-Edit-Mode preview in sync (if present)
if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
    _G.MSUF_UpdateBossCastbarPreview()
end
end

-- -------------------------------------------------
-- Visual / Frame builder (match MSUF's castbar layout)
-- -------------------------------------------------
local function CreateBossCastbarFrame(unit)
    local name = "MSUF_" .. unit .. "CastBar"
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetClampedToScreen(true)
    frame.unit = unit
    frame._msufBarKey = unit
    frame._msufCastState = frame._msufCastState or {}
    frame.reverseFill = false -- legacy flag; actual fill controlled via MSUF_GetCastbarReverseFillForFrame()
    frame.MSUF_isNotInterruptiblePlain = false
    frame.isNotInterruptible = false
    frame.MSUF_timerDriven = true


    -- default size; will be resized to match MSUF boss frame width during UpdateAnchor()
    frame:SetSize(250, 18)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)

    -- Background (solid black like MSUF)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0, 0, 0, 1)
    frame.background = background

    if _G.MSUF_ApplyCastbarOutline then _G.MSUF_ApplyCastbarOutline(frame, true) end

    -- StatusBar (shifted right to make room for the icon so it never overlaps the fill)
    local statusBar = CreateFrame("StatusBar", nil, frame)
    frame.statusBar = statusBar

    -- Empower first-cast fix (boss):
    -- On the first empower cast, StatusBar:GetWidth() can still be 0/1 when we try to
    -- lay out stage tick markers, which sets frame.MSUF_empowerLayoutPending=true.
    -- Re-run the layout once the bar is actually sized/visible so empower visuals
    -- show correctly on the *first* cast (not only starting with the second one).
    if statusBar and statusBar.HookScript and not statusBar._msufEmpowerLayoutHooked then
        statusBar._msufEmpowerLayoutHooked = true
        statusBar:HookScript("OnSizeChanged", function()
            if frame and frame.isEmpower and frame.MSUF_empowerLayoutPending and type(_G.MSUF_LayoutEmpowerTicks) == "function" then
                _G.MSUF_LayoutEmpowerTicks(frame)
            end
        end)
    end
    if frame and frame.HookScript and not frame._msufEmpowerShowHooked then
        frame._msufEmpowerShowHooked = true
        frame:HookScript("OnShow", function(f)
            if f and f.isEmpower and f.MSUF_empowerLayoutPending and type(_G.MSUF_LayoutEmpowerTicks) == "function" then
                _G.MSUF_LayoutEmpowerTicks(f)
            end
        end)
    end

    -- Icon (anchored to the frame left, not inside the bar)
    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon = icon

    -- Background bar (same texture, darker)
    local backgroundBar = statusBar:CreateTexture(nil, "BACKGROUND")
    backgroundBar:SetAllPoints(statusBar)
    local __bg = nil
    if type(_G.MSUF_GetCastbarBackgroundTexture) == "function" then
        __bg = _G.MSUF_GetCastbarBackgroundTexture()
    end
    if not __bg or __bg == "" then
        __bg = (type(_G.MSUF_GetCastbarTexture) == "function" and _G.MSUF_GetCastbarTexture()) or "Interface\\TargetingFrame\\UI-StatusBar"
    end
    backgroundBar:SetTexture(__bg)
    frame.backgroundBar = backgroundBar

    -- Texts (inside statusbar region)
    local castText = statusBar:CreateFontString(nil, "OVERLAY")
    local _fp, _ff, _fr, _fg, _fb, _fs, _shadow = MSUF_GetGlobalFontPack_Boss()
    castText:SetFont(_fp, _fs, _ff)
    castText:SetTextColor(_fr, _fg, _fb, 1)
    if _shadow then
        castText:SetShadowColor(0, 0, 0, 1)
        castText:SetShadowOffset(1, -1)
    else
        castText:SetShadowOffset(0, 0)
    end
    castText:SetJustifyH("LEFT")
    frame.castText = castText

    local timeText = statusBar:CreateFontString(nil, "OVERLAY")
    timeText:SetFont(_fp, _fs, _ff)
    timeText:SetTextColor(_fr, _fg, _fb, 1)
    if _shadow then
        timeText:SetShadowColor(0, 0, 0, 1)
        timeText:SetShadowOffset(1, -1)
    else
        timeText:SetShadowOffset(0, 0)
    end
    timeText:SetJustifyH("RIGHT")
    timeText:SetText("")
    frame.timeText = timeText

    -- Position text anchors
    castText:SetPoint("LEFT", statusBar, "LEFT", 2, 0)
    timeText:SetPoint("RIGHT", statusBar, "RIGHT", -2, 0)
    -- Prevent overlap between spell name and time
    castText:SetPoint("RIGHT", timeText, "LEFT", -6, 0)

    function frame:ApplyLayout()
local h = self:GetHeight() or 18
if h < 12 then h = 12 end

-- Boss-specific castbar icon settings (Step 2)
EnsureDBSafe()
local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
local showIcon = (g.showBossCastIcon == nil) and (g.castbarShowIcon ~= false) or (g.showBossCastIcon ~= false)
local iconOffsetX = tonumber(g.bossCastIconOffsetX)
if iconOffsetX == nil then iconOffsetX = tonumber(g.castbarIconOffsetX) end
if iconOffsetX == nil then iconOffsetX = 0 end
local iconOffsetY = tonumber(g.bossCastIconOffsetY)
if iconOffsetY == nil then iconOffsetY = tonumber(g.castbarIconOffsetY) end
if iconOffsetY == nil then iconOffsetY = 0 end
local iconDetached = (iconOffsetX ~= 0 or iconOffsetY ~= 0)

local iconSize = h
if g.bossCastIconSize ~= nil then
    iconSize = tonumber(g.bossCastIconSize) or iconSize
end
if iconSize < 6 then iconSize = 6 end
if iconSize > 128 then iconSize = 128 end

local iconSize = h
if g.bossCastIconSize ~= nil then
    iconSize = tonumber(g.bossCastIconSize) or iconSize
end
if iconSize < 6 then iconSize = 6 end
if iconSize > 128 then iconSize = 128 end

-- Icon area = height x height (or hidden if disabled)
if self.icon then
    self.icon:ClearAllPoints()
    if self.icon.SetParent and self.statusBar then
        if iconDetached then
            self.icon:SetParent(self.statusBar)
        else
            self.icon:SetParent(self)
        end
    end
    if self.icon.SetDrawLayer then
        self.icon:SetDrawLayer("OVERLAY", 7)
    end
    self.icon:SetSize(iconSize, iconSize)
    self.icon:SetPoint("LEFT", self, "LEFT", iconOffsetX, iconOffsetY)
    self.icon:SetShown(showIcon)
end

if self.statusBar then
    self.statusBar:ClearAllPoints()
    -- If the icon is enabled AND not detached, reserve space on the left (no overlap).
    -- If icon is disabled (or detached), the statusbar uses the full width (fixes the "black gap" when icon is off).
    if showIcon and self.icon and not iconDetached then
        self.statusBar:SetPoint("LEFT", self, "LEFT", iconSize + 1, 0)
    else
        self.statusBar:SetPoint("LEFT", self, "LEFT", 0, 0)
    end
    -- 1px top/bottom inset for the same border feel as MSUF
    self.statusBar:SetPoint("TOP", self, "TOP", 0, -1)
    self.statusBar:SetPoint("BOTTOM", self, "BOTTOM", 0, 1)
    self.statusBar:SetPoint("RIGHT", self, "RIGHT", -1, 0)
end

-- Boss cast text offsets (spell name inside the bar)
do
    local textOX = tonumber(g.bossCastTextOffsetX) or 0
    local textOY = tonumber(g.bossCastTextOffsetY) or 0

    local showBossName = (g.showBossCastName ~= false)

    local timeOX = tonumber(g.bossCastTimeOffsetX) or 0
    local timeOY = tonumber(g.bossCastTimeOffsetY) or 0
    local showBossTime = (g.showBossCastTime ~= false)

    -- Base/global size for castbar texts
    local baseSize = g.fontSize or 14
    local globalOverride = tonumber(g.castbarSpellNameFontSize) or 0
    local globalSize = (globalOverride and globalOverride > 0) and globalOverride or baseSize

    -- Boss spell name size: allow boss-only override; otherwise fall back to global
    local bossSize = tonumber(g.bossCastSpellNameFontSize)
    if not bossSize or bossSize < 6 or bossSize > 72 then
        bossSize = globalSize
    else
        bossSize = math.floor(bossSize + 0.5)
    end

    -- Boss cast time size: allow boss-only override; otherwise fall back to global
    local timeSize = tonumber(g.bossCastTimeFontSize)
    if not timeSize or timeSize < 6 or timeSize > 72 then
        timeSize = globalSize
    else
        timeSize = math.floor(timeSize + 0.5)
    end

    if self.castText and self.timeText and self.statusBar then
        self.castText:ClearAllPoints()
        self.timeText:ClearAllPoints()

        self.castText:SetPoint("LEFT", self.statusBar, "LEFT", 2 + textOX, 0 + textOY)
        self.timeText:SetPoint("RIGHT", self.statusBar, "RIGHT", -2 + timeOX, 0 + timeOY)

        -- Prevent overlap between spell name and time (even if time is hidden via alpha)
        self.castText:SetPoint("RIGHT", self.timeText, "LEFT", -6, 0)

        -- Spell name show toggle
        -- Use alpha only (do NOT clear text), so toggling "Show" restores instantly.
        self.castText:Show()
        self.castText:SetAlpha(showBossName and 1 or 0)

        -- Cast time show toggle + size
        self.timeText:Show()
        self.timeText:SetAlpha(showBossTime and 1 or 0)

        local f2, _, fl2 = self.timeText:GetFont()
        if f2 then
            self.timeText:SetFont(f2, timeSize, fl2)
        end

        local f1, _, fl1 = self.castText:GetFont()
        if f1 then
            self.castText:SetFont(f1, bossSize, fl1)
        end
    end
end

local texture = "Interface\\TargetingFrame\\UI-StatusBar"
if type(_G.MSUF_GetCastbarTexture) == "function" then
    local t = SafeCall(_G.MSUF_GetCastbarTexture)
    if t then texture = t end
end

if self.statusBar and self.statusBar.SetStatusBarTexture then
    SafeCall(self.statusBar.SetStatusBarTexture, self.statusBar, texture)
    local sbTex = SafeCall(self.statusBar.GetStatusBarTexture, self.statusBar)
    if sbTex and sbTex.SetHorizTile then
        SafeCall(sbTex.SetHorizTile, sbTex, true)
    end
end

if self.backgroundBar then
    local bgTex = texture
    if type(_G.MSUF_GetCastbarBackgroundTexture) == "function" then
        local t2 = _G.MSUF_GetCastbarBackgroundTexture()
        if t2 and t2 ~= "" then
            bgTex = t2
        end
    end
    SafeCall(self.backgroundBar.SetTexture, self.backgroundBar, bgTex)
    SafeCall(self.backgroundBar.SetVertexColor, self.backgroundBar, 0.176, 0.176, 0.176, 1)
    if self.statusBar then
        self.backgroundBar:ClearAllPoints()
        self.backgroundBar:SetAllPoints(self.statusBar)
    end
end

-- Reverse fill: use MSUF helper so direction stays in sync with your castbar settings.
if self.statusBar and self.statusBar.SetReverseFill then
    local rf = false
    if type(_G.MSUF_GetCastbarReverseFillForFrame) == "function" then
        rf = SafeCall(_G.MSUF_GetCastbarReverseFillForFrame, self, false) or false
    elseif type(_G.MSUF_GetCastbarReverseFill) == "function" then
        rf = SafeCall(_G.MSUF_GetCastbarReverseFill) or false
    end
    SafeCall(self.statusBar.SetReverseFill, self.statusBar, rf and true or false)
end

    end

	-- Interruptible color: mirror MSUF main logic so the Colors menu applies automatically.
	function frame:UpdateColorForInterruptible()
		EnsureDBSafe()
		local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
		-- Refresh raw notInterruptible directly from Unit*Info (same approach as EnhanceQoL/ElvUI):
		--  - More accurate for bosses (events can be missing/delayed).
		--  - Secret-safe: we never boolean-test the raw value; we only pass it into SetVertexColorFromBoolean.
		--  - IMPORTANT: do NOT rely on positional underscore counting; use explicit locals so we always grab the correct return.
		local rawNI
		do
			local u = self.unit
			if u then
				-- Channel first (UnitCastingInfo may not return during channel warm-up/steady-state).
				local chName, chText, chTexture, chStartMS, chEndMS, chIsTrade, chNotInterruptible = UnitChannelInfo(u)
				if chName then
					rawNI = chNotInterruptible
				else
					-- Normal cast
					local caName, caText, caTexture, caStartMS, caEndMS, caIsTrade, caCastID, caNotInterruptible = UnitCastingInfo(u)
					if caName then
						rawNI = caNotInterruptible
					end
				end
				self.MSUF_apiNotInterruptibleRaw = rawNI
			end
		end

		local isNI = (self.MSUF_isNotInterruptiblePlain == true)
		self.isNotInterruptible = isNI
		local ir, ig, ib, ia = nil, nil, nil, 1
		if type(_G.MSUF_GetInterruptibleCastColor) == "function" then
			ir, ig, ib, ia = _G.MSUF_GetInterruptibleCastColor()
		end
		if not (ir and ig and ib) then
			local key = g.castbarInterruptibleColor or "teal"
			local c = (type(_G.MSUF_GetColorFromKey) == "function") and _G.MSUF_GetColorFromKey(key) or nil
			if c and c.GetRGB then
				ir, ig, ib = c:GetRGB()
			end
		end
		if not (ir and ig and ib) then
			ir, ig, ib = 0, 0.85, 0.85
		end

		local nr, ng, nb, na = nil, nil, nil, 1
		if type(_G.MSUF_GetNonInterruptibleCastColor) == "function" then
			nr, ng, nb, na = _G.MSUF_GetNonInterruptibleCastColor()
		end
		if not (nr and ng and nb) then
			local key = g.castbarNonInterruptibleColor or "red"
			local c = (type(_G.MSUF_GetColorFromKey) == "function") and _G.MSUF_GetColorFromKey(key) or nil
			if c and c.GetRGB then
				nr, ng, nb = c:GetRGB()
			end
		end
		if not (nr and ng and nb) then
			nr, ng, nb = 0.9, 0.1, 0.1
		end

		if type(_G.MSUF_Castbar_ApplyNonInterruptibleTint) == "function" then
			_G.MSUF_Castbar_ApplyNonInterruptibleTint(self, rawNI, nr, ng, nb, na, ir, ig, ib, ia, isNI)
		else
			local r = (isNI and nr or ir)
			local gcol = (isNI and ng or ig)
			local b = (isNI and nb or ib)
			local a = (isNI and na or ia)
			if self.statusBar and self.statusBar.SetStatusBarColor then
				self.statusBar:SetStatusBarColor(r, gcol, b, a or 1)
			end
		end
	end

    -- Anchor near its MSUF boss unitframe (if present)
    function frame:UpdateAnchor()
        EnsureDBSafe()
        local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
        local ox = tonumber(g.bossCastbarOffsetX) or 0
        local oy = tonumber(g.bossCastbarOffsetY) or 0
        local forcedW = tonumber(g.bossCastbarWidth)
        local forcedH = tonumber(g.bossCastbarHeight)

        -- Height can always be overridden (even when width is auto-matched to the boss unitframe)
        if forcedH and forcedH > 4 then
            self:SetHeight(forcedH)
        end

        local detached = (g.bossCastbarDetached == true)

        if detached then
            -- Detached: anchor to UIParent CENTER, but keep per-boss vertical stacking.
            local i = tonumber(unit:match("boss(%d+)")) or 1
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", ox, oy - ((i - 1) * 34))

            if forcedW and forcedW > 10 then
                self:SetWidth(forcedW)
            else
                local w = self:GetWidth()
                if not w or w <= 10 then
                    self:SetWidth(240)
                end
            end
        else
            local uf = _G["MSUF_" .. unit] -- e.g. MSUF_boss1
            if uf and uf.GetWidth and uf.GetHeight then
                self:ClearAllPoints()
                self:SetPoint("BOTTOMLEFT", uf, "TOPLEFT", 0 + ox, 2 + oy)

                if forcedW and forcedW > 10 then
                    self:SetWidth(forcedW)
                else
                    local w = uf:GetWidth()
                    if w and w > 10 then
                        self:SetWidth(w)
                    end
                end
            else
                -- fallback: top right, stacked
                local i = tonumber(unit:match("boss(%d+)")) or 1
                self:ClearAllPoints()
                self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -420 + ox, (-220 + oy) - ((i - 1) * 34))

                if forcedW and forcedW > 10 then
                    self:SetWidth(forcedW)
                end
            end
        end

        self:ApplyLayout()
    end

    -- Cast() compatibility: MSUF event logic expects this method name in places
    function frame:Cast()
        BossCastbar_Start(self)
    end

    frame:ApplyLayout()
    frame:UpdateAnchor()
    frame:UpdateColorForInterruptible()
    frame:Hide()
    return frame
end

-- -------------------------------------------------
-- Cast update logic (duration-object driven; uses the central CastbarManager if available)
-- -------------------------------------------------

-- -------------------------------------------------
-- ============================================================================
-- FULLY EVENT-DRIVEN Boss Cast Safety (replaces the 0.25s polling ticker)
-- ============================================================================
-- Instead of a C_Timer.NewTicker that polls UnitExists+UnitCastingInfo every 0.25s,
-- we now use:
--   1. UNIT_HEALTH event → detect boss death mid-cast (registered only while cast active)
--   2. One-shot C_Timer at (expected_cast_end + grace) → absolute failsafe for despawn/phase-out
--   3. INSTANCE_ENCOUNTER_ENGAGE_UNIT → global listener for boss frame composition changes
-- Result: ZERO polling during boss casts. Only event callbacks + 1 deferred check.

BossCastbar_Stop = function(frame)
    if not frame then return end

    -- Cancel any pending interrupt feedback / watchdog timers
    if frame._msufInterruptTimer and frame._msufInterruptTimer.Cancel then
        frame._msufInterruptTimer:Cancel()
    end
    frame._msufInterruptTimer = nil
    frame._msufInterruptFeedbackActive = nil
    frame._msufInterruptFeedbackUntil = nil
    frame.interrupted = nil


    frame.MSUF_durationObj = nil
    frame.MSUF_isChanneled = false
    frame.MSUF_channelDirect = nil
    frame.MSUF_timerRangeSet = nil

    if frame._msufCastState then
        frame._msufCastState.unit = frame.unit
        frame._msufCastState.key = frame._msufBarKey or frame.unit
        frame._msufCastState.active = false
        frame._msufCastState.phase = "IDLE"
        frame._msufCastState.durationObj = nil
        frame._msufCastState.holdUntil = nil
    end

    if _G.MSUF_ClearCastbarTimerDuration and frame.statusBar then
        _G.MSUF_ClearCastbarTimerDuration(frame.statusBar)
    end

    -- Ensure empower visuals never linger.
    Boss_ClearEmpowerState(frame)
    if type(_G.MSUF_SetChannelStaticStripes) == "function" then
        _G.MSUF_SetChannelStaticStripes(frame, false)
    end

    frame.isNotInterruptible = false
    frame.MSUF_apiNotInterruptibleRaw = nil
    if frame.timeText then frame.timeText:SetText("") end

    -- If we're running without a central CastbarManager, ensure we stop driving updates.
    if frame.SetScript then
        frame:SetScript("OnUpdate", nil)
    end

    -- Hard-stop the fill without doing any comparisons on duration values (secret-safe).
    if frame.statusBar and frame.statusBar.SetValue then
        SafeCall(frame.statusBar.SetValue, frame.statusBar, 0)
    end

    if type(_G.MSUF_UnregisterCastbar) == "function" then
        _G.MSUF_UnregisterCastbar(frame)
    end

    frame:Hide()
end
-- Interrupt feedback (optional)
local function BossCastbar_ShowInterruptFeedback(frame, label)
    if not frame then return end
    -- Interrupt feedback is a temporary bar; stop the watchdog so it doesn't instantly hide it.
    local grace = MSUF_GetInterruptFeedbackGrace()
    frame._msufInterruptFeedbackActive = true
    frame._msufInterruptFeedbackUntil = MSUF_Now() + grace
    frame.interrupted = true

    EnsureDBSafe()
    local db = _G.MSUF_DB
    local b = db and db.boss
    if b and b.showInterrupt == false then
        BossCastbar_Stop(frame)
        return
    end

    -- Cancel any pending hide
    if frame._msufInterruptTimer and frame._msufInterruptTimer.Cancel then
        frame._msufInterruptTimer:Cancel()
        frame._msufInterruptTimer = nil
    end

    -- Stop driving updates & clear duration object
    frame.MSUF_durationObj = nil
    frame.MSUF_isChanneled = false
    frame.MSUF_channelDirect = nil
    Boss_ClearEmpowerState(frame)
    if type(_G.MSUF_SetChannelStaticStripes) == "function" then
        _G.MSUF_SetChannelStaticStripes(frame, false)
    end
    frame.MSUF_timerRangeSet = nil

    if _G.MSUF_ClearCastbarTimerDuration and frame.statusBar then
        _G.MSUF_ClearCastbarTimerDuration(frame.statusBar)
    end

    local __st = frame._msufCastState or {}
    frame._msufCastState = __st
    __st.key = frame._msufBarKey or __st.key
    __st.unit = frame.unit
    __st.active = false
    __st.phase = "INTERRUPT"
    __st.durationObj = nil
    __st.holdUntil = MSUF_Now() + grace

    if frame.SetScript then
        frame:SetScript("OnUpdate", nil)
    end

    if type(_G.MSUF_UnregisterCastbar) == "function" then
        _G.MSUF_UnregisterCastbar(frame)
    end

    local txt = label or "Interrupted"

    if frame.statusBar then
        -- Full red bar (no reliance on real timer values)
        SafeCall(frame.statusBar.SetMinMaxValues, frame.statusBar, 0, 1)
        SafeCall(frame.statusBar.SetValue, frame.statusBar, 1)

        if frame.statusBar.SetReverseFill and type(_G.MSUF_GetCastbarReverseFillForFrame) == "function" then
            local rev = SafeCall(_G.MSUF_GetCastbarReverseFillForFrame, frame, false)
            if rev ~= nil then
                SafeCall(frame.statusBar.SetReverseFill, frame.statusBar, rev)
            end
        end

        SafeCall(frame.statusBar.SetStatusBarColor, frame.statusBar, 0.8, 0.1, 0.1, 1)
    end

    if frame.castText then
        frame.castText:SetText(txt)
    end
    if frame.timeText then
        frame.timeText:SetText("")
    end

    frame:Show()

    -- Match the core castbar driver behavior: play shake feedback on interrupts.
    if type(_G.MSUF_PlayCastbarShake) == "function" then
        SafeCall(_G.MSUF_PlayCastbarShake, frame)
    end

    -- EVENT-DRIVEN: Cached per-frame interrupt callback (no new closure per interrupt).
    if _G.C_Timer and _G.C_Timer.NewTimer then
        if not frame._msufInterruptCb then
            frame._msufInterruptCb = function()
                if not frame then return end
                frame._msufInterruptFeedbackActive = nil
                frame._msufInterruptFeedbackUntil = nil
                frame.interrupted = nil

                -- If a new cast started immediately after the interrupt, pick it up.
                local castName = UnitCastingInfo(frame.unit)
                local chanName = UnitChannelInfo(frame.unit)
                if castName or chanName then
                    BossCastbar_Start(frame)
                else
                    BossCastbar_Stop(frame)
                end
            end
        end
        frame._msufInterruptTimer = _G.C_Timer.NewTimer(grace, frame._msufInterruptCb)
    end
end

-- REMOVED: BossCastbar_OnUpdate (per-frame OnUpdate)
-- Boss bar animation is driven natively by Duration Objects (SetTimerDuration).
-- Time text is updated by the central CastbarManager tick (only while cast is active).
-- Zero per-frame cost when CastbarManager is available (always true after addon load).

BossCastbar_Start = function(frame)
    if not frame or not frame.unit then return end
    -- If we just showed interrupt feedback, ignore "restart" attempts for a short grace window.
    if frame._msufInterruptFeedbackActive and frame._msufInterruptFeedbackUntil then
        if MSUF_Now() < frame._msufInterruptFeedbackUntil then
            return
        end
    end

    frame._msufInterruptFeedbackActive = nil
    frame._msufInterruptFeedbackUntil = nil
    frame.interrupted = nil

    -- Cancel any pending interrupt-feedback hide (boss can start a new cast quickly)
    if frame._msufInterruptTimer and frame._msufInterruptTimer.Cancel then
        frame._msufInterruptTimer:Cancel()
        frame._msufInterruptTimer = nil
    end


    if not IsBossCastbarEnabled() then
        BossCastbar_Stop(frame)
        return
    end

    frame:UpdateAnchor()

    -- Prefer casting first
    -- NOTE: the raw API notInterruptible flag can be a *secret value* on Midnight/Beta.
    -- We capture it and store it for C-side vertex tinting only; never boolean-test it in Lua.
    local castName, _, castTex, startTimeMS, endTimeMS, _, _, apiNotInterruptibleRaw = UnitCastingInfo(frame.unit)
    frame.MSUF_apiNotInterruptibleRaw = apiNotInterruptibleRaw

    -- Interruptible state logic is tracked via UNIT_SPELLCAST_(NOT_)INTERRUPTIBLE events
    -- and stored in frame.MSUF_isNotInterruptiblePlain.
    if castName then
        -- Empower support: if we received EMPOWER_START/UPDATE, attempt to switch this bar into empower mode.
        -- This makes boss empower castbars match the player visuals (stage ticks/segments + stage feedback).
        if frame.MSUF_wantsEmpower then
            local castUnit = MSUF_GetCanonicalCastUnitForBoss(frame.unit)
            local tl = Boss_BuildEmpowerTimeline(castUnit, startTimeMS, endTimeMS)

            if tl and tl.stageEnds and tl.totalBase and tl.totalBase > 0 then
                -- Reset any previous cast state.
                Boss_ClearEmpowerState(frame)
                frame.MSUF_durationObj = nil
                frame.MSUF_isChanneled = false
                frame.MSUF_channelDirect = nil
                frame.MSUF_timerRangeSet = nil
                if type(_G.MSUF_SetChannelStaticStripes) == "function" then
                    _G.MSUF_SetChannelStaticStripes(frame, false)
                end

                frame.isEmpower = true
                frame.empowerStartTime = tl.castStartSec
                frame.empowerStageEnds = tl.stageEnds
                frame.empowerTotalBase = tl.totalBase
                frame.empowerTotalWithGrace = tl.totalWithGrace
                frame.empowerNextStage = 1
                frame.MSUF_empowerLayoutPending = true

                if frame.statusBar and frame.statusBar.SetMinMaxValues and frame.statusBar.SetValue then
                    SafeCall(frame.statusBar.SetMinMaxValues, frame.statusBar, 0, tl.totalWithGrace)
                    local now = MSUF_Now()
                    local elapsed = now - (tl.castStartSec or now)
                    if elapsed < 0 then elapsed = 0 end
                    SafeCall(frame.statusBar.SetValue, frame.statusBar, elapsed)
                end

                -- Apply fill direction for empowered casts.
                if frame.statusBar and frame.statusBar.SetReverseFill and type(_G.MSUF_GetCastbarReverseFillForFrame) == "function" then
                    local rev = SafeCall(_G.MSUF_GetCastbarReverseFillForFrame, frame, true)
                    if rev ~= nil then
                        SafeCall(frame.statusBar.SetReverseFill, frame.statusBar, rev and true or false)
                    end
                end

                -- Ensure ticks/segments are laid out immediately.
                if type(_G.MSUF_LayoutEmpowerTicks) == "function" then
                    SafeCall(_G.MSUF_LayoutEmpowerTicks, frame)
                end

                if frame.SetScript then
                    -- Empower bars are driven by CastbarManager (fast tick interval).
                    frame:SetScript("OnUpdate", nil)
                end

                frame.castText:SetText(castName or "")
                if frame.icon then frame.icon:SetTexture(castTex or nil) end

                frame:UpdateColorForInterruptible()
                frame:Show()

                if type(_G.MSUF_RegisterCastbar) == "function" then
                    -- Force manager to re-evaluate tick rate (empower wants ~0.03).
                    frame._msufTickInterval = nil
                    frame._msufNextTick = nil
                    _G.MSUF_RegisterCastbar(frame)
                end
                return
            else
                -- Stage data not yet available; retry briefly a few times.
                frame.MSUF_empowerRetryCount = (frame.MSUF_empowerRetryCount or 0) + 1
                if frame.MSUF_empowerRetryCount <= 6 and not frame.MSUF_empowerRetryActive and _G.C_Timer and _G.C_Timer.After then
                    frame.MSUF_empowerRetryActive = true
                    if not frame._msufEmpowerRetryCb then
                        frame._msufEmpowerRetryCb = function()
                            if not frame then return end
                            frame.MSUF_empowerRetryActive = nil
                            if frame.unit and UnitExists(frame.unit) and UnitCastingInfo(frame.unit) then
                                BossCastbar_Start(frame)
                            end
                        end
                    end
                    _G.C_Timer.After(0.05, frame._msufEmpowerRetryCb)
                end
            end
        else
            -- Not empower; ensure we don't keep empower visuals from a previous cast.
            if frame.isEmpower then
                Boss_ClearEmpowerState(frame)
            end
        end

        local castUnit = MSUF_GetCanonicalCastUnitForBoss(frame.unit)
        local durObj = SafeCall(UnitCastingDuration, castUnit)
        if not durObj then
            frame.castText:SetText(castName or "")
            if frame.icon then frame.icon:SetTexture(castTex or nil) end
            if type(_G.MSUF_SetChannelStaticStripes) == "function" then
                _G.MSUF_SetChannelStaticStripes(frame, false)
            end
            frame:UpdateColorForInterruptible()
        frame:Show()
            return
        end

        frame.MSUF_isChanneled = false
        frame.MSUF_channelDirect = nil
        if type(_G.MSUF_SetChannelStaticStripes) == "function" then
            _G.MSUF_SetChannelStaticStripes(frame, false)
        end
        frame.MSUF_timerRangeSet = nil
        frame.MSUF_durationObj = durObj
        local __st = frame._msufCastState or {}
        frame._msufCastState = __st
        __st.key = frame._msufBarKey or __st.key
        __st.unit = frame.unit
        __st.active = true
        __st.phase = "CHANNEL"
        __st.durationObj = durObj
        local __st = frame._msufCastState or {}
        frame._msufCastState = __st
        __st.key = frame._msufBarKey or __st.key
        __st.unit = frame.unit
        __st.active = true
        __st.phase = "CAST"
        __st.durationObj = durObj
        do
            local st = frame._msufCastState or {}
            frame._msufCastState = st
            st.key = frame._msufBarKey or st.key
            st.unit = frame.unit
            st.active = true
            st.phase = "CAST"
            st.durationObj = durObj
        end
        if frame._msufCastState then
            frame._msufCastState.unit = frame.unit
            frame._msufCastState.key = frame._msufBarKey
            frame._msufCastState.active = true
            frame._msufCastState.phase = (frame.isEmpower and 'EMPOWER') or (frame.MSUF_isChanneled and 'CHANNEL') or 'CAST'
            frame._msufCastState.durationObj = durObj
            frame._msufCastState.holdUntil = nil
        end

        if frame.statusBar and frame.statusBar.SetTimerDuration then
            SafeCall(frame.statusBar.SetTimerDuration, frame.statusBar, durObj, 0)
        end
	    

        -- Apply fill direction immediately for this cast type.
        if frame.statusBar and frame.statusBar.SetReverseFill and type(_G.MSUF_GetCastbarReverseFillForFrame) == "function" then
            local rev = SafeCall(_G.MSUF_GetCastbarReverseFillForFrame, frame, false)
            if rev ~= nil then
                SafeCall(frame.statusBar.SetReverseFill, frame.statusBar, rev and true or false)
            end
        end
-- FULLY EVENT-DRIVEN: Always use CastbarManager for time-text updates (no OnUpdate).
        -- Bar animation is driven natively by Duration Objects via SetTimerDuration.
        if frame.SetScript then
            frame:SetScript("OnUpdate", nil)
        end
        frame.castText:SetText(castName or "")
        if frame.icon then frame.icon:SetTexture(castTex or nil) end

        frame:UpdateColorForInterruptible()
        frame:Show()

        if type(_G.MSUF_RegisterCastbar) == "function" then
            _G.MSUF_RegisterCastbar(frame)
        end
        return
    end

    -- Channel
    -- If the unit switches to a channel, ensure empower visuals/state are cleared.
    if frame.isEmpower or frame.MSUF_wantsEmpower then
        Boss_ClearEmpowerState(frame)
    end
    -- Secret-safe capture: raw notInterruptible can be a secret value; store only (no boolean tests).
    local chanName, _, chanTex, _, _, _, apiNotInterruptibleRaw = UnitChannelInfo(frame.unit)
    frame.MSUF_apiNotInterruptibleRaw = apiNotInterruptibleRaw
    -- Interruptible state handled by UNIT_SPELLCAST_(NOT_)INTERRUPTIBLE events (see BossCastbar_OnEvent).
    if chanName then
        local castUnit = MSUF_GetCanonicalCastUnitForBoss(frame.unit)
        local durObj = SafeCall(UnitChannelDuration, castUnit)
        if not durObj then
            frame.castText:SetText(chanName or "")
            if frame.icon then frame.icon:SetTexture(chanTex or nil) end
            if type(_G.MSUF_SetChannelStaticStripes) == "function" then
                _G.MSUF_SetChannelStaticStripes(frame, true)
            end
            frame:UpdateColorForInterruptible()
        frame:Show()
            return
        end

        frame.MSUF_isChanneled = true
        frame.MSUF_channelDirect = true
        if type(_G.MSUF_SetChannelStaticStripes) == "function" then
            _G.MSUF_SetChannelStaticStripes(frame, true)
        end
        frame.MSUF_timerRangeSet = nil
        frame.MSUF_durationObj = durObj
        if frame._msufCastState then
            frame._msufCastState.unit = frame.unit
            frame._msufCastState.key = frame._msufBarKey
            frame._msufCastState.active = true
            frame._msufCastState.phase = (frame.isEmpower and 'EMPOWER') or (frame.MSUF_isChanneled and 'CHANNEL') or 'CAST'
            frame._msufCastState.durationObj = durObj
            frame._msufCastState.holdUntil = nil
        end

        if frame.statusBar and frame.statusBar.SetTimerDuration then
            SafeCall(frame.statusBar.SetTimerDuration, frame.statusBar, durObj, 0)
        end
	    

        -- Apply fill direction immediately for this cast type.
        if frame.statusBar and frame.statusBar.SetReverseFill and type(_G.MSUF_GetCastbarReverseFillForFrame) == "function" then
            local rev = SafeCall(_G.MSUF_GetCastbarReverseFillForFrame, frame, true)
            if rev ~= nil then
                SafeCall(frame.statusBar.SetReverseFill, frame.statusBar, rev and true or false)
            end
        end
-- FULLY EVENT-DRIVEN: Always use CastbarManager (no OnUpdate fallback).
        if frame.SetScript then
            frame:SetScript("OnUpdate", nil)
        end
        frame.castText:SetText(chanName or "")
        if frame.icon then frame.icon:SetTexture(chanTex or nil) end

        frame:UpdateColorForInterruptible()
        frame:Show()

        if type(_G.MSUF_RegisterCastbar) == "function" then
            _G.MSUF_RegisterCastbar(frame)
        end
        return
    end

    BossCastbar_Stop(frame)
end

-- PERF FIX Boss-C: Cached per-frame deferred start.
-- Instead of creating a new C_Timer.After(0, function()..end) closure on every event,
-- each boss frame gets a single cached callback. A dirty flag prevents duplicate timers
-- when multiple events fire in the same frame (e.g. STOP + START on channel refresh).
-- This eliminates ~60-120 closure allocations/minute during boss encounters.
local function MSUF_Boss_ScheduleStart(frame)
    if not frame or not frame.unit then return end
    if frame._msufStartPending then return end  -- already scheduled this frame
    frame._msufStartPending = true

    -- Create cached callback once per frame (first use)
    if not frame._msufCachedStartCb then
        frame._msufCachedStartCb = function()
            frame._msufStartPending = nil
            if frame and frame.unit then
                BossCastbar_Start(frame)
            end
        end
    end

    C_Timer.After(0, frame._msufCachedStartCb)
end

local function BossCastbar_OnEvent(self, event, ...)
    local unit = ...
    -- Event args (12.0):
    --  START:          unitTarget, castGUID, spellID
    --  STOP:           unitTarget, castGUID, spellID
    --  INTERRUPTED:    unitTarget, castGUID, spellID, interruptedBy
    --  CHANNEL_STOP:   unitTarget, castGUID, spellID, interruptedBy
    --  EMPOWER_STOP:   unitTarget, castGUID, spellID, complete, interruptedBy
    local castGUID = select(2, ...)
    local spellID  = select(3, ...)
    local arg4     = select(4, ...)
    local arg5     = select(5, ...)

    -- UNIT_* events provide unit as first arg; ignore other units
    if event:match("^UNIT_") and unit and unit ~= self.unit then
        return
    end
    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        self.MSUF_isNotInterruptiblePlain = false
        self.isNotInterruptible = false
        self:UpdateColorForInterruptible()
        -- PERF FIX: Skip full :Cast() resync; only the color changed, not the cast itself.
        return
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        self.MSUF_isNotInterruptiblePlain = true
        self.isNotInterruptible = true
        self:UpdateColorForInterruptible()
        -- PERF FIX: Skip full :Cast() resync; only the color changed, not the cast itself.
        return
    end

    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- Some boss interrupts fire this event; others only report via *_STOP interruptedBy.
        -- We treat either as interrupt feedback.
        BossCastbar_ShowInterruptFeedback(self, "Interrupted")
        return
    end

	-- Track empower intent so BossCastbar_Start can switch into empower mode.
	if event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
	    self.MSUF_wantsEmpower = true
	elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
	    self.MSUF_wantsEmpower = nil
	end

    -- Boss units often do NOT fire UNIT_SPELLCAST_INTERRUPTED reliably in Midnight.
    -- In 12.0, the reliable source is the interruptedBy flag on CHANNEL_STOP / EMPOWER_STOP.
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local interruptedBy = (arg4 == true)
        if interruptedBy then
            BossCastbar_ShowInterruptFeedback(self, "Interrupted")
            return
        end
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        local interruptedBy = (arg5 == true)
        if interruptedBy then
            BossCastbar_ShowInterruptFeedback(self, "Interrupted")
            return
        end
    end

    if event == "PLAYER_ENTERING_WORLD" then
        self:UpdateAnchor()
        -- Use cached deferred start (see below) instead of creating a new closure
        MSUF_Boss_ScheduleStart(self)
        return
    end

	if event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_DELAYED"
	    or event == "UNIT_SPELLCAST_EMPOWER_START"
	    or event == "UNIT_SPELLCAST_EMPOWER_UPDATE"
	    or event == "UNIT_SPELLCAST_EMPOWER_STOP"
    then
        -- PERF FIX: Use a cached per-frame callback instead of creating a new closure on every event.
        MSUF_Boss_ScheduleStart(self)
    end
end

-- -------------------------------------------------
-- Module init
-- -------------------------------------------------
local function InitBossCastbars()
    if _G.MSUF_BossCastbars then return end
    _G.MSUF_BossCastbars = {}

    for i = 1, MAX_BOSS do
        local unit = "boss" .. i
        local f = CreateBossCastbarFrame(unit)
        _G.MSUF_BossCastbars[i] = f

        -- events
        f:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)

        f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", unit)

	    -- Empower (rare for bosses, but supported)
	    f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", unit)
	    f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", unit)
	    f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", unit)

        f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unit)

        f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)

        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", BossCastbar_OnEvent)

        -- Late-load safety: if a boss is already casting when we load/reload, refresh once.
        C_Timer.After(0.1, function()
            if f and f.unit then BossCastbar_Start(f) end
        end)
    end

    -- EVENT-DRIVEN: Global listener for boss frame composition changes.
    -- INSTANCE_ENCOUNTER_ENGAGE_UNIT fires when bosses appear/disappear in instances.
    -- This catches the edge case where a boss despawns mid-cast without UNIT_SPELLCAST_STOP.
    local bossEngageFrame = CreateFrame("Frame")
    bossEngageFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    bossEngageFrame:SetScript("OnEvent", function()
        local frames = _G.MSUF_BossCastbars
        if not frames then return end
        for i = 1, #frames do
            local f = frames[i]
            if f and f:IsShown() and f.unit and not f._msufInterruptFeedbackActive then
                if not UnitExists(f.unit) then
                    BossCastbar_Stop(f)
                end
            end
        end
    end)

    -- Apply global castbar visuals/fonts now that boss castbars exist
    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end

    -- Apply saved cast time visibility
    ApplyBossCastbarTimeSetting()

    -- Respect saved toggle immediately
    if type(_G.MSUF_ApplyBossCastbarsEnabled) == "function" then
        _G.MSUF_ApplyBossCastbarsEnabled()
    end
end


-- -------------------------------------------------
-- 
local function ApplyBossCastbarPositionSetting()
    EnsureDBSafe()
    local frames = _G.MSUF_BossCastbars
    if not frames then return end

    for i = 1, #frames do
        local f = frames[i]
        if f and f.UpdateAnchor then
            f:UpdateAnchor()
        end
        if f and f.ApplyLayout then
            f:ApplyLayout()
        end
    end
-- Keep Castbar-Edit-Mode preview in sync (if present)
if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
    _G.MSUF_UpdateBossCastbarPreview()
end
end

-- --------------------------------------------------
-- Boss Castbar Preview (Castbar Edit Mode only)
-- --------------------------------------------------
-- Multi-preview upgrade:
-- If Boss unitframe previews show boss1..bossN, we show a matching castbar preview for each visible boss frame.
-- Boss castbar previews remain DETACHED (anchored to UIParent) and are positioned relative to each boss unitframe preview.

local function MSUF_GetBossPreviewCount()
    -- Prefer Blizzard constant if present
    local n = tonumber(_G.MAX_BOSS_FRAMES)
    if not n or n < 1 or n > 12 then
        n = 5
    end
    return n
end

local function MSUF_HideAllBossCastbarPreviews()
    if _G.MSUF_BossCastbarPreview then
        _G.MSUF_BossCastbarPreview:Hide()
    end
    local max = MSUF_GetBossPreviewCount()
    for i = 2, max do
        local f = _G["MSUF_BossCastbarPreview" .. i]
        if f then f:Hide() end
    end
end

-- --------------------------------------------------
-- Boss Castbar Preview helpers (Edit Mode)
-- --------------------------------------------------

-- Always show a deterministic "fake" icon in boss castbar previews so the user can position it
-- even if gameplay icons are disabled.
local MSUF_BOSS_PREVIEW_FAKE_ICON = 136235 -- generic spell icon (safe across builds)

local function MSUF_ApplyInterruptiblePreviewColor(f)
    if not f or not f.statusBar or not f.statusBar.SetStatusBarColor then return end

    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}

    local r, gg, b

    local function ResolveColorKey(key, fallbackKey)
        if type(_G.MSUF_GetColorFromKey) == "function" then
            local c = _G.MSUF_GetColorFromKey(key)
            if c and type(c) == "table" and c.GetRGB then
                local rr, rg, rb = c:GetRGB()
                return rr, rg, rb
            end
            if type(c) == "number" then
                -- Some older implementations return r,g,b directly.
                return c, select(2, _G.MSUF_GetColorFromKey(key))
            end
        end
        return GetColorFromKeyFallback(fallbackKey or key)
    end

    if type(_G.MSUF_GetInterruptibleCastColor) == "function" then
        r, gg, b = _G.MSUF_GetInterruptibleCastColor()
    end

    if not (r and gg and b) then
        local key = g.castbarInterruptibleColor or "turquoise"
        r, gg, b = ResolveColorKey(key, key)
    end

    if not (r and gg and b) then
        r, gg, b = 0.2, 0.8, 0.8
    end

    SafeCall(f.statusBar.SetStatusBarColor, f.statusBar, r, gg, b, 1)
end

local function MSUF_CreateBossCastbarPreview(index)
    index = tonumber(index) or 1
    if index < 1 then index = 1 end

    -- Keep boss1 name stable for compatibility
    if index == 1 and _G.MSUF_BossCastbarPreview then
        return _G.MSUF_BossCastbarPreview
    end

    local name = (index == 1) and "MSUF_BossCastbarPreview" or ("MSUF_BossCastbarPreview" .. index)
    local existing = _G[name]
    if existing then
        if index == 1 then _G.MSUF_BossCastbarPreview = existing end
        return existing
    end

    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetSize(240, 12)
    -- Enabled so any Boss castbar preview can be clicked in MSUF Edit Mode to open the Boss castbar popup.
    f:EnableMouse(true)
    f._msufBossPreviewIndex = index
    f.unit = "boss"

    -- simple border like the other preview bars
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0, 0, 0, 0.55)
        f:SetBackdropBorderColor(0, 0, 0, 1)
    end

    local statusBar = CreateFrame("StatusBar", nil, f)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0.6)
    statusBar:SetPoint("TOP", f, "TOP", 0, -1)
    statusBar:SetPoint("BOTTOM", f, "BOTTOM", 0, 1)
    statusBar:SetPoint("RIGHT", f, "RIGHT", -1, 0)
    statusBar:SetPoint("LEFT", f, "LEFT", 1, 0)
    f.statusBar = statusBar

	-- Text overlay frame: FontStrings must be ABOVE the StatusBar fill.
	-- If they are parented to the preview frame (f), the StatusBar (child frame, higher framelevel)
	-- can visually cover them as the bar fills. Parent the texts to an overlay frame above the StatusBar.
	local textOverlay = CreateFrame("Frame", nil, f)
	textOverlay:SetAllPoints(statusBar)
	if textOverlay.SetFrameLevel and statusBar.GetFrameLevel then
		textOverlay:SetFrameLevel(statusBar:GetFrameLevel() + 10)
	end
	f._msufTextOverlay = textOverlay

    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(statusBar)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetAlpha(0.25)
    f.backgroundBar = bg

    local icon = f:CreateTexture(nil, "OVERLAY", nil, 7)
    -- Deterministic fake icon (preview only). Add a fallback path in case fileIDs behave oddly.
    if icon and icon.SetTexture then
        local ok = pcall(icon.SetTexture, icon, MSUF_BOSS_PREVIEW_FAKE_ICON)
        if not ok then
            pcall(icon.SetTexture, icon, "Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end
    if icon and icon.SetTexCoord then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if icon and icon.SetVertexColor then
        icon:SetVertexColor(1, 1, 1, 1)
    end
    f.icon = icon

	local castText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castText:SetJustifyH("LEFT")
    castText:SetText("Boss castbar preview")
    f.castText = castText

	local timeText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetJustifyH("RIGHT")
    timeText:SetText("3.2")
    f.timeText = timeText

    if _G.MSUF_ApplyCastbarOutline then _G.MSUF_ApplyCastbarOutline(f, true) end

    
    -- Wire the standard Castbar Preview Edit handlers (drag + click-to-open popup).
    -- IMPORTANT: Always treat boss2..bossN previews as kind "boss" so they open the Boss popup.
    if type(_G.MSUF_SetupCastbarPreviewEditHandlers) == "function" then
        _G.MSUF_SetupCastbarPreviewEditHandlers(f, "boss")
    end
-- Keep boss1 global stable
    if index == 1 then
        _G.MSUF_BossCastbarPreview = f
    end

    return f
end

local function MSUF_ApplyBossCastbarPreviewLayout(f, index)
    if not f then return end
    index = tonumber(index) or f._msufBossPreviewIndex or 1

    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}

    local forcedW = tonumber(g.bossCastbarWidth)
    local forcedH = tonumber(g.bossCastbarHeight)

    local uf = _G["MSUF_boss" .. index] or _G["MSUF_boss1"]
    local w = (forcedW and forcedW > 10) and forcedW or (uf and uf.GetWidth and uf:GetWidth()) or 240
    local h = (forcedH and forcedH > 4) and forcedH or 12

    -- Icon size: when bossCastIconSize is set, it overrides the default (bar height).
    local iconSize = h
    if g.bossCastIconSize ~= nil then
        iconSize = tonumber(g.bossCastIconSize) or iconSize
    end
    if iconSize < 6 then iconSize = 6 end
    if iconSize > 128 then iconSize = 128 end

    f:SetSize(w, h)

    -- Preview behavior: ALWAYS show the icon in MSUF Edit Mode so the user can position it
    -- even if gameplay icons are disabled.
    local showIcon = true
    local iconOffsetX = tonumber(g.bossCastIconOffsetX)
    if iconOffsetX == nil then iconOffsetX = tonumber(g.castbarIconOffsetX) end
    if iconOffsetX == nil then iconOffsetX = 0 end
    local iconOffsetY = tonumber(g.bossCastIconOffsetY)
    if iconOffsetY == nil then iconOffsetY = tonumber(g.castbarIconOffsetY) end
    if iconOffsetY == nil then iconOffsetY = 0 end
    local iconDetached = (iconOffsetX ~= 0 or iconOffsetY ~= 0)

    if f.icon then
        if f.icon.SetTexture then
            -- Deterministic fake icon (preview only). Add a fallback path in case fileIDs behave oddly.
            local ok = pcall(f.icon.SetTexture, f.icon, MSUF_BOSS_PREVIEW_FAKE_ICON)
            if not ok then
                pcall(f.icon.SetTexture, f.icon, "Interface\\Icons\\INV_Misc_QuestionMark")
            end
        end
        if f.icon.SetTexCoord then
            f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if f.icon.SetVertexColor then
            f.icon:SetVertexColor(1, 1, 1, 1)
        end
        f.icon:ClearAllPoints()
        if f.icon.SetParent and f.statusBar then
            if iconDetached then
                f.icon:SetParent(f.statusBar)
            else
                f.icon:SetParent(f)
            end
        end
        if f.icon.SetDrawLayer then
            f.icon:SetDrawLayer("OVERLAY", 7)
        end
        f.icon:SetSize(iconSize, iconSize)
        f.icon:SetPoint("LEFT", f, "LEFT", iconOffsetX, iconOffsetY)
        f.icon:SetShown(showIcon)
    end

    if f.statusBar then
        f.statusBar:ClearAllPoints()

        if showIcon and f.icon and not iconDetached then
            f.statusBar:SetPoint("LEFT", f, "LEFT", iconSize + 1, 0)
        else
            f.statusBar:SetPoint("LEFT", f, "LEFT", 1, 0)
        end

        f.statusBar:SetPoint("TOP", f, "TOP", 0, -1)
        f.statusBar:SetPoint("BOTTOM", f, "BOTTOM", 0, 1)
        f.statusBar:SetPoint("RIGHT", f, "RIGHT", -1, 0)
    end

    -- texture (if the helper exists)
    do
        local t
        if type(_G.MSUF_RefreshCastbarStyleCache) == "function" then
            SafeCall(_G.MSUF_RefreshCastbarStyleCache, f)
        end
        t = f.MSUF_cachedCastbarTexture or SafeCall(_G.MSUF_GetCastbarTexture)
        if t and f.statusBar and f.statusBar.SetStatusBarTexture then
            SafeCall(f.statusBar.SetStatusBarTexture, f.statusBar, t)
        end
        if t and f.backgroundBar then
            local bgTex = t
            if type(_G.MSUF_GetCastbarBackgroundTexture) == "function" then
                local t2 = _G.MSUF_GetCastbarBackgroundTexture()
                if t2 and t2 ~= "" then
                    bgTex = t2
                end
            end
            SafeCall(f.backgroundBar.SetTexture, f.backgroundBar, bgTex)
        end
    end

    -- Force the preview bar to use the *interruptible* cast color, mirroring the real boss castbar
    -- resolution so the Colors menu applies.
    MSUF_ApplyInterruptiblePreviewColor(f)

    -- boss cast text offsets (spell name inside the bar)
    local textOX = tonumber(g.bossCastTextOffsetX) or 0
    local textOY = tonumber(g.bossCastTextOffsetY) or 0

    local timeOX = tonumber(g.bossCastTimeOffsetX) or 0
    local timeOY = tonumber(g.bossCastTimeOffsetY) or 0

	-- Ensure preview texts are always ABOVE the StatusBar fill.
	-- Older builds created FontStrings on the parent preview frame (f), which can be covered by the child StatusBar.
	local textOverlay = f._msufTextOverlay
	if (not textOverlay) and f.statusBar and type(CreateFrame) == "function" then
		textOverlay = CreateFrame("Frame", nil, f)
		textOverlay:SetAllPoints(f.statusBar)
		if textOverlay.SetFrameLevel and f.statusBar.GetFrameLevel then
			textOverlay:SetFrameLevel(f.statusBar:GetFrameLevel() + 10)
		end
		f._msufTextOverlay = textOverlay
	end
	if textOverlay then
		if f.castText and f.castText.SetParent then
			pcall(f.castText.SetParent, f.castText, textOverlay)
		end
		if f.timeText and f.timeText.SetParent then
			pcall(f.timeText.SetParent, f.timeText, textOverlay)
		end
	end

	if f.castText and f.timeText and f.statusBar then
        f.castText:ClearAllPoints()
        f.timeText:ClearAllPoints()

        f.castText:SetPoint("LEFT", f.statusBar, "LEFT", 2 + textOX, 0 + textOY)
        f.timeText:SetPoint("RIGHT", f.statusBar, "RIGHT", -2 + timeOX, 0 + timeOY)

        -- Prevent overlap between spell name and time (even if time is hidden via alpha)
        f.castText:SetPoint("RIGHT", f.timeText, "LEFT", -6, 0)

        local showTime = (g.showBossCastTime ~= false)
        f.timeText:Show()
        f.timeText:SetAlpha(showTime and 1 or 0)

        local showBossName = (g.showBossCastName ~= false)
        f.castText:Show()
        f.castText:SetAlpha(showBossName and 1 or 0)

        -- font sizes: boss-only override for spell name/time, otherwise fall back to global
        local baseSize = g.fontSize or 14
        local globalOverride = tonumber(g.castbarSpellNameFontSize) or 0
        local globalSize = (globalOverride and globalOverride > 0) and globalOverride or baseSize

        local bossSize = tonumber(g.bossCastSpellNameFontSize)
        if not bossSize or bossSize < 6 or bossSize > 72 then
            bossSize = globalSize
        else
            bossSize = math.floor(bossSize + 0.5)
        end

        local timeSize = tonumber(g.bossCastTimeFontSize)
        if not timeSize or timeSize < 6 or timeSize > 72 then
            timeSize = globalSize
        else
            timeSize = math.floor(timeSize + 0.5)
        end

        local font1, _, flags1 = f.castText:GetFont()
        if font1 then f.castText:SetFont(font1, bossSize, flags1) end

        local font2, _, flags2 = f.timeText:GetFont()
        if font2 then f.timeText:SetFont(font2, timeSize, flags2) end
    end
end

local function MSUF_PositionBossCastbarPreview(f, index)
    if not f then return end
    index = tonumber(index) or f._msufBossPreviewIndex or 1

    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local ox = tonumber(g.bossCastbarOffsetX) or 0
    local oy = tonumber(g.bossCastbarOffsetY) or 0

    if g.bossCastbarDetached == true then
        -- Detached: anchor to UIParent CENTER, keep per-boss vertical stacking.
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", ox, oy - ((index - 1) * 24))
        return
    end

    local uf = _G["MSUF_boss" .. index]
    if uf and uf.IsShown and uf:IsShown() then
        f:ClearAllPoints()
        -- Keep legacy relative placement, but previews themselves stay parented to UIParent.
        f:SetPoint("BOTTOMLEFT", uf, "TOPLEFT", 0 + ox, 2 + oy)
    else
        -- fallback if boss frames aren't visible (still useful for slider tweaking)
        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -320, -200 - ((index - 1) * 24))
    end
end


function _G.MSUF_UpdateBossCastbarPreview()
    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}

    -- Hard gate: never show boss preview when Boss Frames are disabled, or outside MSUF Edit Mode.
    if ((_G.MSUF_DB and _G.MSUF_DB.boss and _G.MSUF_DB.boss.enabled == false) or (_G.MSUF_UnitEditModeActive ~= true)) then
        MSUF_HideAllBossCastbarPreviews()
        return
    end

    -- Only in Castbar Edit Mode
    if not g.castbarPlayerPreviewEnabled then
        MSUF_HideAllBossCastbarPreviews()
        return
    end

    -- Respect "Enable Boss castbar"
    if g.enableBossCastbar == false then
        MSUF_HideAllBossCastbarPreviews()
        return
    end

    local max = MSUF_GetBossPreviewCount()
    for i = 1, max do
        local uf = _G["MSUF_boss" .. i]
        local f = MSUF_CreateBossCastbarPreview(i)

        -- Only show a preview when the corresponding boss unitframe preview exists & is visible.
        if uf and uf.IsShown and uf:IsShown() then
            MSUF_PositionBossCastbarPreview(f, i)
            MSUF_ApplyBossCastbarPreviewLayout(f, i)
            f:Show()
        else
            f:Hide()
        end
    end
end


-- Public API (Options Toggle)

function _G.MSUF_ApplyBossCastbarTimeSetting()
    ApplyBossCastbarTimeSetting()
end

function _G.MSUF_ApplyBossCastbarPositionSetting()
    ApplyBossCastbarPositionSetting()
end


-- -------------------------------------------------
function _G.MSUF_SetBossCastbarsEnabled(enabled)
    EnsureDBSafe()

    -- Persist (nil/true = enabled, false = disabled)
    if _G.MSUF_DB and _G.MSUF_DB.general then
        _G.MSUF_DB.general.enableBossCastbar = enabled and true or false
    end

    local frames = _G.MSUF_BossCastbars
    if not frames then return end

    if enabled then
        for i = 1, #frames do
            local f = frames[i]
            if f then BossCastbar_Start(f) end
        end
    else
        for i = 1, #frames do
            local f = frames[i]
            if f then BossCastbar_Stop(f) end
        end
    end

    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end
-- Keep Castbar-Edit-Mode preview in sync (if present)
if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
    _G.MSUF_UpdateBossCastbarPreview()
end
end

function _G.MSUF_ApplyBossCastbarsEnabled()
    EnsureDBSafe()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    local enabled = (not g) or (g.enableBossCastbar ~= false)
    _G.MSUF_SetBossCastbarsEnabled(enabled)
end

-- Boot (ADDON_LOADED for our addon)
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, loadedName)
    if loadedName ~= addonName then return end
    C_Timer.After(0, InitBossCastbars)
end)
