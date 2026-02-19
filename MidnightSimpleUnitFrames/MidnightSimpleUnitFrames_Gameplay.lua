-- MidnightSimpleUnitFrames_Gameplay.lua
-- Gameplay helpers for Midnight Simple Unit Frames.
-- Gameplay module: combat timer, combat state text, combat crosshair, and other small helpers.
local _, ns = ...
ns = ns or {}

------------------------------------------------------
-- Local shortcuts / libs
------------------------------------------------------
local CreateFrame   = CreateFrame
local UIParent      = UIParent
local pairs         = pairs
local C_NamePlate   = C_NamePlate
local C_Spell       = C_Spell
local C_SpellBook   = C_SpellBook
local UnitExists    = UnitExists
local UnitCanAttack = UnitCanAttack
local GetTime             = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local InCombatLockdown    = InCombatLockdown
local GetNamePlates       = C_NamePlate and C_NamePlate.GetNamePlates
local string_format       = string.format
local GetCVar    = GetCVar
local GetCVarBool = GetCVarBool
local math_min     = math.min
local math_max     = math.max
local IsAltKeyDown  = IsAltKeyDown
------------------------------------------------------
-- Small math helpers
------------------------------------------------------
local _MSUF_Clamp = _G._MSUF_Clamp
if not _MSUF_Clamp then
    _MSUF_Clamp = function(v, mn, mx)
        v = tonumber(v)
        if not v then
            return mn
        end
        if v < mn then
            return mn
        end
        if v > mx then
            return mx
        end
        return v
    end
    _G._MSUF_Clamp = _MSUF_Clamp
end

local C_Timer      = C_Timer
local C_Timer_After = C_Timer and C_Timer.After

------------------------------------------------------
-- Apply queue: coalesce multiple option changes into a single Apply per frame
------------------------------------------------------
do
    local _applyPending = false

    function ns.MSUF_RequestGameplayApply()
        if _applyPending then
            return
        end
        _applyPending = true

        if C_Timer_After then
            C_Timer_After(0, function()
                _applyPending = false
                if ns and ns.MSUF_ApplyGameplayVisuals then
                    ns.MSUF_ApplyGameplayVisuals()
                end
            end)
        else
            _applyPending = false
            if ns and ns.MSUF_ApplyGameplayVisuals then
                ns.MSUF_ApplyGameplayVisuals()
            end
        end
    end
end

local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetCameraZoom = GetCameraZoom
local GetNumSpellTabs       = GetNumSpellTabs
local GetSpellTabInfo       = GetSpellTabInfo
local GetSpellBookItemInfo  = GetSpellBookItemInfo
local GetSpellBookItemName  = GetSpellBookItemName
local GetSpellInfo          = GetSpellInfo
local string_lower          = string.lower
local tostring              = tostring
local tonumber              = tonumber
local table_sort            = table.sort
local ipairs                = ipairs

local LibStub       = LibStub
local LSM           = LibStub and LibStub("LibSharedMedia-3.0", true)

------------------------------------------------------
-- UpdateManager accessor (avoid repeating global lookups everywhere)
------------------------------------------------------
-- MSUF_GetUpdateManager removed (Phase 7A): UpdateManager no longer exists.

------------------------------------------------------
-- SavedVars helper (own sub-table under MSUF_DB)
------------------------------------------------------
local gameplayDBCache

local function EnsureGameplayDefaults()
    if type(MSUF_DB) ~= "table" then
        MSUF_DB = {}
    end
    if type(MSUF_DB.gameplay) ~= "table" then
        MSUF_DB.gameplay = {}
    end

    local g = MSUF_DB.gameplay

    if g.nameplateMeleeSpellID == nil then
        g.nameplateMeleeSpellID = 0
    end

    if g.combatOffsetX == nil then
        g.combatOffsetX = 0
    end
    if g.combatOffsetY == nil then
        g.combatOffsetY = -200
    end
    -- In-combat timer toggle
    if g.enableCombatTimer == nil then
        g.enableCombatTimer = false
    end
    -- Absolute pixel size override for the combat timer text.
    if g.combatFontSize == nil or g.combatFontSize <= 0 then
        g.combatFontSize = 24
    end
    if g.combatFontSize < 10 then
        g.combatFontSize = 10
    elseif g.combatFontSize > 64 then
        g.combatFontSize = 64
    end
    -- Lock state for combat timer (shares the same frame, but has its own toggle)
    if g.lockCombatTimer == nil then
        g.lockCombatTimer = false
    end

    -- Anchor target for the combat timer (none/player/target/focus)
    if g.combatTimerAnchor == nil then
        g.combatTimerAnchor = "none"
    end
    -- Combat timer text color (configured from the Colors menu)
    if type(g.combatTimerColor) ~= "table" then
        g.combatTimerColor = { 1, 1, 1 } -- default white
    end

    -- Independent position and lock for combat enter/leave text
    if g.combatStateOffsetX == nil then
        g.combatStateOffsetX = 0
    end
    if g.combatStateOffsetY == nil then
        g.combatStateOffsetY = 80
    end
    if g.lockCombatState == nil then
        g.lockCombatState = false
    end

    -- Absolute pixel size override for combat enter/leave text.
    if g.combatStateFontSize == nil or g.combatStateFontSize <= 0 then
        g.combatStateFontSize = 24
    end
    if g.combatStateFontSize < 10 then
        g.combatStateFontSize = 10
    elseif g.combatStateFontSize > 64 then
        g.combatStateFontSize = 64
    end

    -- Duration that combat enter/leave text stays visible (in seconds)
    if g.combatStateDuration == nil then
        g.combatStateDuration = 1.5
    end

    if g.enableCombatStateText == nil then
        g.enableCombatStateText = false
    end

    -- Customizable combat enter/leave strings (shown briefly on regen events)
    if g.combatStateEnterText == nil then
        g.combatStateEnterText = "+Combat"
    end
    if g.combatStateLeaveText == nil then
        g.combatStateLeaveText = "-Combat"
    end

-- Combat state text colors (configured from the Colors menu)
-- Stored as {r,g,b}. Defaults match the legacy hardcoded colors:
--  Enter = white, Leave = light gray.
if g.combatStateEnterColor == nil then
    g.combatStateEnterColor = { 1, 1, 1 }
end
if g.combatStateLeaveColor == nil then
    g.combatStateLeaveColor = { 0.7, 0.7, 0.7 }
end
if g.combatStateColorSync == nil then
    g.combatStateColorSync = false
end

    -- Rogue "The First Dance" timer (6s after leaving combat, uses combat state text)
    if g.enableFirstDanceTimer == nil then
        g.enableFirstDanceTimer = false
    end

    -- Green combat crosshair under player while in combat
    if g.enableCombatCrosshair == nil then
        g.enableCombatCrosshair = false
    end

    -- Combat crosshair thickness (line width in pixels)
    if g.crosshairThickness == nil then
        g.crosshairThickness = 2
    end

    -- Combat crosshair size (overall crosshair size in pixels)
    if g.crosshairSize == nil then
        g.crosshairSize = 40
    end

    -- Combat crosshair: color by melee range (uses the shared melee spell selection)
    -- Green = in melee range, Red = out of melee range
    if g.enableCombatCrosshairMeleeRangeColor == nil then
        g.enableCombatCrosshairMeleeRangeColor = false
    end
    -- Combat crosshair range colors
    if type(g.crosshairInRangeColor) ~= "table" then
        g.crosshairInRangeColor = { 0, 1, 0 } -- default green
    end
    if type(g.crosshairOutRangeColor) ~= "table" then
        g.crosshairOutRangeColor = { 1, 0, 0 } -- default red
    end
    -- Cooldown manager icon mode (for MSUF_CooldownIcons module)
    -- Default OFF to avoid idle CPU when the external viewer/module is present.
    -- TEMPORARILY DISABLED: CooldownManager "bars as icons" mode will be reworked.
    -- Keep the key for backward compatibility, but hard-force OFF for now.
    g.cooldownIcons = false

    -- Shaman: player totem tracker (player-only for now)
    -- Default ON for Shamans on first run; otherwise default OFF.
    if g.enablePlayerTotems == nil then
        local isShaman = false
        if UnitClass then
            local _, cls = UnitClass("player")
            isShaman = (cls == "SHAMAN")
        end
        g.enablePlayerTotems = isShaman and true or false
    end
    if g.playerTotemsShowText == nil then
        g.playerTotemsShowText = true
    end
    if g.playerTotemsScaleTextByIconSize == nil then
        g.playerTotemsScaleTextByIconSize = true
    end
    if g.playerTotemsIconSize == nil or g.playerTotemsIconSize <= 0 then
        g.playerTotemsIconSize = 24
    end
    if g.playerTotemsSpacing == nil then
        g.playerTotemsSpacing = 4
    end
    if g.playerTotemsOffsetX == nil then
        g.playerTotemsOffsetX = 0
    end
    if g.playerTotemsOffsetY == nil then
        g.playerTotemsOffsetY = -6
    end
    if type(g.playerTotemsAnchorFrom) ~= "string" or g.playerTotemsAnchorFrom == "" then
        g.playerTotemsAnchorFrom = "TOPLEFT"
    end
    if type(g.playerTotemsAnchorTo) ~= "string" or g.playerTotemsAnchorTo == "" then
        g.playerTotemsAnchorTo = "BOTTOMLEFT"
    end
    if g.playerTotemsGrowthDirection ~= "LEFT" and g.playerTotemsGrowthDirection ~= "RIGHT"
        and g.playerTotemsGrowthDirection ~= "UP" and g.playerTotemsGrowthDirection ~= "DOWN" then
        g.playerTotemsGrowthDirection = "RIGHT"
    end
    if g.playerTotemsFontSize == nil or g.playerTotemsFontSize <= 0 then
        g.playerTotemsFontSize = 14
    end
    if type(g.playerTotemsTextColor) ~= "table" then
        g.playerTotemsTextColor = { 1, 1, 1 }
    end


    -- Party Interrupt Tracker (Kick tracker)
    if g.enableKickTracker == nil then
        g.enableKickTracker = false
    end
    if g.lockKickTracker == nil then
        g.lockKickTracker = false
    end
    if g.kickTrackerOffsetX == nil then
        g.kickTrackerOffsetX = 0
    end
    if g.kickTrackerOffsetY == nil then
        g.kickTrackerOffsetY = -140
    end
    if g.kickTrackerWidth == nil then
        g.kickTrackerWidth = 220
    end
    if g.kickTrackerIconSize == nil then
        g.kickTrackerIconSize = 26
    end
    if g.kickTrackerSpacing == nil then
        g.kickTrackerSpacing = 4
    end
    if g.kickTrackerFontSize == nil or g.kickTrackerFontSize <= 0 then
        g.kickTrackerFontSize = 14
    end
    if g.kickTrackerShowNames == nil then
        g.kickTrackerShowNames = true
    end
    if g.kickTrackerShowReady == nil then
        g.kickTrackerShowReady = true
    end
    if g.kickTrackerShowInDungeon == nil then
        g.kickTrackerShowInDungeon = true
    end
    if g.kickTrackerShowInOpenWorld == nil then
        g.kickTrackerShowInOpenWorld = true
    end
    if g.kickTrackerShowInRaid == nil then
        g.kickTrackerShowInRaid = false
    end


    if g.kickTrackerBgAlpha == nil then
        g.kickTrackerBgAlpha = 0.35
    end
    g.kickTrackerBgAlpha = _MSUF_Clamp(tonumber(g.kickTrackerBgAlpha) or 0.35, 0, 1)

    -- Clamp to sane ranges (avoid layout blowups from bad profiles)
    g.kickTrackerWidth = _MSUF_Clamp(g.kickTrackerWidth, 160, 420)
    g.kickTrackerIconSize = _MSUF_Clamp(g.kickTrackerIconSize, 14, 48)
    g.kickTrackerSpacing = _MSUF_Clamp(g.kickTrackerSpacing, 0, 18)
    g.kickTrackerFontSize = _MSUF_Clamp(g.kickTrackerFontSize, 8, 28)

    -- One-time tip popup flag
    if g.shownGameplayColorsTip == nil then
        g.shownGameplayColorsTip = false
    end

    gameplayDBCache = g
    return g
end

-- Hotpath helper: avoid calling EnsureGameplayDefaults() every tick.
-- The gameplay DB table is stable; this cache is refreshed whenever EnsureGameplayDefaults() runs.
local function GetGameplayDBFast()
    if type(gameplayDBCache) == "table" then
        return gameplayDBCache
    end
    return EnsureGameplayDefaults()
end

------------------------------------------------------
-- Cooldown Manager Icon Mode: hard stop idle CPU
--
-- The CooldownManagerIcons integration can become a tiny but permanent idle CPU
-- contributor if the external viewer keeps an OnUpdate alive while hidden.
-- We keep it event-driven by syncing the icon module state on viewer show/hide
-- (and on login), with a single coalesced request (no persistent OnUpdate here).
------------------------------------------------------
do
    local _hooked = false
    local _pending = false

    local function _Run()
        _pending = false
        EnsureGameplayDefaults()

        local fn = _G and _G.MSUF_ApplyCooldownIconMode
        if type(fn) == "function" then
            -- Optional module: keep errors visible during dev; but don't hard-break login.
            pcall(fn)
            return
        end

        -- Fallback for older builds: just let the icon module decide whether to keep OnUpdate alive.
        fn = _G and _G.MSUF_CDIcons_UpdateOnUpdateState
        if type(fn) == "function" then
            pcall(fn)
        end
    end

    local function RequestSync()
        if _pending then return end
        _pending = true
        if C_Timer_After then
            C_Timer_After(0, _Run)
        else
            _Run()
        end
    end

    -- Expose for Options panel handlers (keeps all call sites consistent).
    if ns then
        ns.MSUF_RequestCooldownIconsSync = RequestSync
    end

    local function TryHook()
        if _hooked then return end
        local ecv = _G and _G["EssentialCooldownViewer"]
        if not ecv or not ecv.HookScript then return end
        _hooked = true

        ecv:HookScript("OnShow", RequestSync)
        ecv:HookScript("OnHide", RequestSync)
        ecv:HookScript("OnSizeChanged", RequestSync)

        RequestSync()
    end

    local function ScheduleHookAttempts()
        local tries = 0
        local function attempt()
            tries = tries + 1
            TryHook()
            if (not _hooked) and tries < 10 and C_Timer_After then
                C_Timer_After(1, attempt)
            end
        end
        if C_Timer_After then
            C_Timer_After(1, attempt)
        else
            attempt()
        end
    end

    RequestSync()
    ScheduleHookAttempts()
end

------------------------------------------------------
-- One-time tip popup: gameplay colors live in Colors â†’ Gameplay
------------------------------------------------------
do
    local POPUP_KEY = "MSUF_GAMEPLAY_COLORS_TIP"

    local function EnsureDialog()
        if not _G.StaticPopupDialogs then
            return false
        end
        if not _G.StaticPopupDialogs[POPUP_KEY] then
            _G.StaticPopupDialogs[POPUP_KEY] = {
                -- ASCII only (avoid missing glyph boxes in some fonts)
                text = "Tip: Gameplay colors are in Colors > Gameplay",
                button1 = OKAY,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
        end
        return true
    end

    function ns.MSUF_MaybeShowGameplayColorsTip()
        local g = EnsureGameplayDefaults()
        if g and g.shownGameplayColorsTip then
            return
        end
        if EnsureDialog() and _G.StaticPopup_Show then
            -- Mark as shown before showing so we never spam, even if the dialog is dismissed instantly.
            if g then
                g.shownGameplayColorsTip = true
            end
            _G.StaticPopup_Show(POPUP_KEY)
        end
    end
end

------------------------------------------------------
-- Font helper: reuse global MSUF text style
------------------------------------------------------
local function GetGameplayFontSettings(kind)
    local gGameplay = EnsureGameplayDefaults()

    local general = (MSUF_DB and MSUF_DB.general) or {}

    -- FONT PATH
    local fontPath

    local fontKey = general.fontKey
    if LSM and fontKey and fontKey ~= "" then
        local fetched = LSM:Fetch("font", fontKey, true)
        if fetched then
            fontPath = fetched
        end
    end

    if not fontPath or fontPath == "" then
        fontPath = "Fonts/FRIZQT__.TTF"
    end

    -- FONT FLAGS (outline)
    local flags
    if general.noOutline then
        flags = ""
    elseif general.boldText then
        flags = "THICKOUTLINE"
    else
        flags = "OUTLINE"
    end

    -- FONT COLOR (reuse MSUF_FONT_COLORS global)
    local colorKey = (general.fontColor or "white"):lower()
    local colorTbl = (MSUF_FONT_COLORS and MSUF_FONT_COLORS[colorKey]) or (MSUF_FONT_COLORS and MSUF_FONT_COLORS.white) or {1, 1, 1}
    local fr, fg, fb = colorTbl[1], colorTbl[2], colorTbl[3]

    -- BASE SIZE + optional gameplay override
    local baseSize  = general.fontSize or 14
    local override

    if kind == "timer" then
        -- In-combat timer text
        override = gGameplay.combatFontSize or 0
    elseif kind == "state" then
        -- Combat enter/leave text (falls back to combat timer size if 0)
        override = gGameplay.combatStateFontSize
        if not override or override == 0 then
            override = gGameplay.combatFontSize or 0
        end
    else
        -- Other gameplay texts
        override = gGameplay.fontSize or 0
    end
    local effSize
    if override > 0 then
        effSize = override
    else
        effSize = math.floor(baseSize * 1.6 + 0.5)
    end

    local useShadow = general.textBackdrop and true or false

    return fontPath, flags, fr, fg, fb, effSize, useShadow
end

------------------------------------------------------
-- Combat state text colors (Enter/Leave)
------------------------------------------------------
local function _MSUF_NormalizeRGB(tbl, dr, dg, db)
    if type(tbl) == "table" then
        local r = tonumber(tbl[1])
        local g = tonumber(tbl[2])
        local b = tonumber(tbl[3])
        if r and g and b then
            if r < 0 then r = 0 elseif r > 1 then r = 1 end
            if g < 0 then g = 0 elseif g > 1 then g = 1 end
            if b < 0 then b = 0 elseif b > 1 then b = 1 end
            return r, g, b
        end
    end
    return dr or 1, dg or 1, db or 1
end

local function MSUF_GetCombatStateColors(g)
    -- Defaults match the legacy hardcoded values.
    local er, eg, eb = _MSUF_NormalizeRGB(g and g.combatStateEnterColor, 1, 1, 1)
    local lr, lg, lb = _MSUF_NormalizeRGB(g and g.combatStateLeaveColor, 0.7, 0.7, 0.7)

    if g and g.combatStateColorSync then
        lr, lg, lb = er, eg, eb
    end
    return er, eg, eb, lr, lg, lb
end

local function MSUF_ApplyCombatStateDynamicColor()
    if not combatStateText and EnsureCombatStateText then
        EnsureCombatStateText()
    end

    if not combatStateText then
        return
    end
    local g = GetGameplayDBFast()
    local er, eg, eb, lr, lg, lb = MSUF_GetCombatStateColors(g)

    local st = combatStateText._msufLastState
    if st == "leave" or st == "dance" then
        combatStateText:SetTextColor(lr, lg, lb, 1)
    else
        combatStateText:SetTextColor(er, eg, eb, 1)
    end
end

------------------------------------------------------
-- Gameplay frames
------------------------------------------------------
local combatFrame
local combatTimerText
local combatStateFrame
local combatStateText
local combatEventFrame
local MSUF_CombatState_OnEvent  -- forward declaration (Phase 7B: used by EventBus)
local combatCrosshairFrame
local combatCrosshairEventFrame

-- Forward declarations (helpers are referenced before their definitions below)
local MSUF_CrosshairHasValidTarget
local MSUF_RefreshCrosshairRangeTaskEnabled
local MSUF_RequestCrosshairRangeRefresh
local EnsureFirstDanceTaskRegistered
-- Resolve the spell ID used for crosshair melee-range checks, with robust fallbacks.
local function MSUF_ResolveCrosshairRangeSpellIDFromGameplay(g)
    if type(g) ~= "table" then return 0 end

    local spellID = tonumber(g.crosshairRangeSpellID) or 0
    if spellID <= 0 then
        -- Backward-compat fallback (older builds used meleeRangeSpellID)
        spellID = tonumber(g.meleeRangeSpellID) or 0
    end
    if spellID <= 0 then
        -- New: optional per-class storage for the shared melee-range spell.
        -- If enabled and a class entry exists, prefer that.
        if g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
            local _, class = UnitClass("player")
            if class then
                local perClass = tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0
                if perClass > 0 then
                    spellID = perClass
                end
            end
        end

        -- Older/shared selector builds stored this under nameplateMeleeSpellID
        if spellID <= 0 then
            spellID = tonumber(g.nameplateMeleeSpellID) or 0
        end
    end
    if spellID <= 0 and MSUF_DB and type(MSUF_DB.general) == "table" then
        -- Extra legacy fallback (very old builds)
        spellID = tonumber(MSUF_DB.general.meleeRangeSpellID) or 0
    end

    return spellID
end

-- Cache crosshair runtime flags from gameplay DB so hotpaths don't repeatedly look up DB keys.
local function MSUF_CrosshairSyncRangeCacheFromGameplay(g)
    if not combatCrosshairFrame then return end

    combatCrosshairFrame._msufCrosshairEnabled = (g and g.enableCombatCrosshair) and true or false

    local spellID = MSUF_ResolveCrosshairRangeSpellIDFromGameplay(g)
    combatCrosshairFrame._msufRangeSpellID = spellID

    -- Only treat range-color as active if the toggle is on AND we can resolve a valid spell.
    combatCrosshairFrame._msufUseRangeColor = (g and g.enableCombatCrosshairMeleeRangeColor) and (spellID > 0) or false

    -- Cache crosshair range colors on the frame (avoid DB lookups in hotpaths)
    local inT = g and g.crosshairInRangeColor
    combatCrosshairFrame._msufInRangeR = (inT and inT[1]) or 0
    combatCrosshairFrame._msufInRangeG = (inT and inT[2]) or 1
    combatCrosshairFrame._msufInRangeB = (inT and inT[3]) or 0

    local outT = g and g.crosshairOutRangeColor
    combatCrosshairFrame._msufOutRangeR = (outT and outT[1]) or 1
    combatCrosshairFrame._msufOutRangeG = (outT and outT[2]) or 0
    combatCrosshairFrame._msufOutRangeB = (outT and outT[3]) or 0
    -- Dynamic interval: fast while it matters (combat + valid target); otherwise we keep the task disabled.
    combatCrosshairFrame._msufRangeTickInterval = 0.25
end

-- In-combat timer state
local combatStartTime = nil
local wasInCombat = false
local lastTimerText = ""

-- Shared combat timer tick (used by UpdateManager + immediate event refresh)
local function MSUF_Gameplay_TickCombatTimer()
    if not combatTimerText then
        return
    end

    local gNow = GetGameplayDBFast()
    if not gNow or not gNow.enableCombatTimer then
        -- Clear immediately when disabled
        if lastTimerText ~= "" then
            lastTimerText = ""
            combatTimerText:SetText("")
        end
        wasInCombat = false
        combatStartTime = nil
        return
    end

    -- UnitAffectingCombat is the most reliable signal for "combat started" timing.
    -- InCombatLockdown is a safe fallback.
    local inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) or (InCombatLockdown and InCombatLockdown()) or false

    if inCombat then
        local now = GetTime()
        if not combatStartTime then
            combatStartTime = now
        end
        wasInCombat = true

        local elapsedCombat = now - combatStartTime
        if elapsedCombat < 0 then
            elapsedCombat = 0
        end

        local m = math.floor(elapsedCombat / 60)
        local s = math.floor(elapsedCombat % 60)
        local text = string_format("%d:%02d", m, s)
        if text ~= lastTimerText then
            lastTimerText = text
            combatTimerText:SetText(text)
        end
    else
        -- Out of combat: show preview only when unlocked & enabled
        if not gNow.lockCombatTimer then
            if lastTimerText ~= "0:00" then
                lastTimerText = "0:00"
                combatTimerText:SetText("0:00")
            end
        else
            if lastTimerText ~= "" then
                lastTimerText = ""
                combatTimerText:SetText("")
            end
        end
        wasInCombat = false
        combatStartTime = nil
    end
end

-- Rogue "The First Dance" 6s window (out-of-combat)
local FIRST_DANCE_WINDOW = 6
local firstDanceActive = false
local firstDanceEndTime = 0
local firstDanceLastText = nil

local _TickFirstDance  -- forward declaration (defined after StartFirstDanceWindow)

-- Phase 7A: stop the FirstDance OnUpdate tick (event-driven start/stop)
local function _StopFirstDanceTick()
    firstDanceActive = false
    firstDanceEndTime = 0
    firstDanceLastText = nil
    if combatStateFrame then combatStateFrame:SetScript("OnUpdate", nil) end
end

-- Make the combat enter/leave text click-through while it is actively displayed
-- so it never steals clicks / focus (e.g. targeting) while flashing on screen.
-- When cleared, mouse is restored based on the lock setting.
local function MSUF_CombatState_SetClickThrough(active)
    if not combatStateFrame then
        return
    end

    if active then
        combatStateFrame._msufClickThroughActive = true
        combatStateFrame:EnableMouse(false)
        return
    end

    combatStateFrame._msufClickThroughActive = nil
    local g = GetGameplayDBFast()
    if g and g.lockCombatState then
        combatStateFrame:EnableMouse(false)
    else
        combatStateFrame:EnableMouse(true)
    end
end

local function ApplyFontToCounter()
    -- If nothing exists yet, nothing to do
    if not combatTimerText and not combatStateText then
        return
    end
    -- Combat timer font (uses its own override)
    if combatTimerText then
        local path, flags, r, g, b, size, useShadow = GetGameplayFontSettings("timer")
        combatTimerText:SetFont(path or "Fonts/FRIZQT__.TTF", size or 20, flags or "OUTLINE")
        local gdb = GetGameplayDBFast()
        local tr, tg, tb = _MSUF_NormalizeRGB(gdb and gdb.combatTimerColor, r or 1, g or 1, b or 1)
        combatTimerText:SetTextColor(tr, tg, tb, 1)
        if useShadow then
            combatTimerText:SetShadowOffset(1, -1)
            combatTimerText:SetShadowColor(0, 0, 0, 1)
        else
            combatTimerText:SetShadowOffset(0, 0)
        end
    end

    -- Combat state text font (shares combat font settings)
    if combatStateText then
        local path, flags, r, g, b, size, useShadow = GetGameplayFontSettings("state")
        combatStateText:SetFont(path or "Fonts/FRIZQT__.TTF", (size or 24), flags or "OUTLINE")
        combatStateText:SetTextColor(r or 1, g or 1, b or 1, 1)
        if useShadow then
            combatStateText:SetShadowOffset(1, -1)
            combatStateText:SetShadowColor(0, 0, 0, 1)
        else
            combatStateText:SetShadowOffset(0, 0)
        end
        -- If the combat state text is currently visible, keep its configured Enter/Leave color.
        MSUF_ApplyCombatStateDynamicColor()
    end

end

local EnsureCombatStateText

------------------------------------------------------
-- "The First Dance" helper
------------------------------------------------------
local function StartFirstDanceWindow()
    local g = GetGameplayDBFast()

    -- Feature off = make sure state is hard-reset and updater is off
    if not g.enableFirstDanceTimer then
        _StopFirstDanceTick()

        MSUF_CombatState_SetClickThrough(false)
        return
    end

    if not combatStateText and EnsureCombatStateText then
        EnsureCombatStateText()
    end

    if not combatStateText then
        MSUF_CombatState_SetClickThrough(false)
        return
    end

    firstDanceEndTime = GetTime() + FIRST_DANCE_WINDOW
    firstDanceActive = true
    firstDanceLastText = nil

    -- Make sure font / shadow are up to date
    local path, flags, r, gCol, bCol, size, useShadow = GetGameplayFontSettings("state")
    combatStateText:SetFont(path or "Fonts/FRIZQT__.TTF", (size or 24), flags or "OUTLINE")
    local _er, _eg, _eb, lr, lg, lb = MSUF_GetCombatStateColors(g)
    combatStateText._msufLastState = "dance"
    combatStateText:SetTextColor(lr, lg, lb, 1)
    if useShadow then
        combatStateText:SetShadowOffset(1, -1)
        combatStateText:SetShadowColor(0, 0, 0, 1)
    else
        combatStateText:SetShadowOffset(0, 0)
    end

    MSUF_CombatState_SetClickThrough(true)

    combatStateText:Show()

    -- Start the tick for this animation window
    if combatStateFrame then
        combatStateFrame:SetScript("OnUpdate", function(self, elapsed)
            _TickFirstDance()
        end)
    end

end

------------------------------------------------------
-- Combat state text (enter/leave combat)
------------------------------------------------------
EnsureCombatStateText = function()
    if combatStateText then
        return
    end

    local g = GetGameplayDBFast()

    if not combatStateFrame then
        combatStateFrame = CreateFrame("Frame", "MSUF_CombatStateFrame", UIParent)
        combatStateFrame:SetSize(220, 60)
        combatStateFrame:SetPoint("CENTER", UIParent, "CENTER", g.combatStateOffsetX or 0, g.combatStateOffsetY or 80)
        combatStateFrame:SetFrameStrata("DIALOG")
        combatStateFrame:SetClampedToScreen(true)
        combatStateFrame:SetMovable(true)
        combatStateFrame:RegisterForDrag("LeftButton")

        combatStateFrame:SetScript("OnDragStart", function(self)
            local gd = EnsureGameplayDefaults()
            if gd.lockCombatState then
                return
            end
            self:StartMoving()
        end)

        combatStateFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
        local x, y = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            local dx = x - ux
            local dy = y - uy
            local db = EnsureGameplayDefaults()
            db.combatStateOffsetX = dx
            db.combatStateOffsetY = dy
        end)
    end

    combatStateText = combatStateFrame:CreateFontString("MSUF_CombatStateText", "OVERLAY")
    combatStateText:SetPoint("CENTER")

    -- Use gameplay combat font settings
    local path, flags, r, gCol, bCol, size, useShadow = GetGameplayFontSettings("state")
    combatStateText:SetFont(path or "Fonts/FRIZQT__.TTF", (size or 24), flags or "OUTLINE")
    local _er, _eg, _eb, lr, lg, lb = MSUF_GetCombatStateColors(g)
    combatStateText._msufLastState = "dance"
    combatStateText:SetTextColor(lr, lg, lb, 1)

    if useShadow then
        combatStateText:SetShadowOffset(1, -1)
        combatStateText:SetShadowColor(0, 0, 0, 1)
    else
        combatStateText:SetShadowOffset(0, 0)
    end

    combatStateText:SetText("")
    combatStateText:Hide()

    if not combatEventFrame then
        combatEventFrame = true  -- sentinel: frame replaced by EventBus (Phase 7B)
MSUF_CombatState_OnEvent = function(event)
    local g = GetGameplayDBFast()
    if not g or (not g.enableCombatStateText and not g.enableFirstDanceTimer) then
        if combatStateText then
            combatStateText:SetText("")
            combatStateText:Hide()
            MSUF_CombatState_SetClickThrough(false)
        end
        MSUF_CombatState_SetClickThrough(false)
        -- Always hard-stop First Dance if feature is disabled
        _StopFirstDanceTick()

        return
    end

    local wantState = (g.enableCombatStateText == true)
    local wantDance = (g.enableFirstDanceTimer == true)

    local duration = g.combatStateDuration or 1.5
    if duration < 0.1 then
        duration = 0.1
    end

    if event == "PLAYER_REGEN_DISABLED" then
        -- Enter combat: "+Combat"
        _StopFirstDanceTick()

        if not wantState then
            if combatStateText then
                combatStateText:SetText("")
                combatStateText:Hide()
            end
            MSUF_CombatState_SetClickThrough(false)
            return
        end

        local enterText = g.combatStateEnterText
        if type(enterText) ~= "string" or enterText == "" then
            enterText = "+Combat"
        end

        local er, eg, eb = MSUF_GetCombatStateColors(g)
        combatStateText._msufLastState = "enter"
        combatStateText:SetTextColor(er, eg, eb, 1)
        combatStateText:SetText(enterText)
        MSUF_CombatState_SetClickThrough(true)
        combatStateText:Show()

        if C_Timer_After then
            C_Timer_After(duration, function()
                local g2 = GetGameplayDBFast()
                if combatStateText and g2 and g2.enableCombatStateText then
                    combatStateText:SetText("")
                    combatStateText:Hide()
                    MSUF_CombatState_SetClickThrough(false)
                end
            end)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leave combat: "-Combat" OR First Dance timer
        _StopFirstDanceTick()

        if g.enableFirstDanceTimer then
            StartFirstDanceWindow()
            return
        end

        if not wantState then
            if combatStateText then
                combatStateText:SetText("")
                combatStateText:Hide()
            end
            MSUF_CombatState_SetClickThrough(false)
            return
        end

        local leaveText = g.combatStateLeaveText
        if type(leaveText) ~= "string" or leaveText == "" then
            leaveText = "-Combat"
        end

        local _er, _eg, _eb, lr, lg, lb = MSUF_GetCombatStateColors(g)
        combatStateText._msufLastState = "leave"
        combatStateText:SetTextColor(lr, lg, lb, 1)
        combatStateText:SetText(leaveText)
        MSUF_CombatState_SetClickThrough(true)
        combatStateText:Show()

        if C_Timer_After then
            C_Timer_After(duration, function()
                local g2 = GetGameplayDBFast()
                if combatStateText and g2 and g2.enableCombatStateText then
                    combatStateText:SetText("")
                    combatStateText:Hide()
                    MSUF_CombatState_SetClickThrough(false)
                end
            end)
        end
    end
end
-- Phase 7B: combatEventFrame → EventBus. Registration handled in Apply path.
    end

end

------------------------------------------------------
-- "First Dance" countdown tick
------------------------------------------------------
_TickFirstDance = function()
    if not firstDanceActive then
        return
    end

    local gFD = GetGameplayDBFast()
    if not gFD.enableFirstDanceTimer then
        _StopFirstDanceTick()

        if combatStateText then
            combatStateText:SetText("")
            combatStateText:Hide()
        end
        MSUF_CombatState_SetClickThrough(false)
        return
    end

    if not combatStateText and EnsureCombatStateText then
        EnsureCombatStateText()
    end

    if not combatStateText then
        MSUF_CombatState_SetClickThrough(false)
        return
    end

    local now = GetTime()
    local remaining = firstDanceEndTime - now
    if remaining <= 0 then
        _StopFirstDanceTick()

        combatStateText:SetText("")
        combatStateText:Hide()
        MSUF_CombatState_SetClickThrough(false)
        return
    end

    local text = string_format("First Dance: %.1f", remaining)
    if text ~= firstDanceLastText then
        firstDanceLastText = text
        combatStateText:SetText(text)
    end
end

EnsureFirstDanceTaskRegistered = function()
    -- Phase 7A: OnUpdate is now started/stopped directly in StartFirstDanceWindow/_TickFirstDance.
    -- This function is kept as a no-op for any callers that still reference it.
end

------------------------------------------------------
-- Combat crosshair (simple green crosshair at player feet)
------------------------------------------------------

-- Returns true if any Blizzard "find yourself" / self highlight or
-- personal nameplate setting is active so we let the crosshair
-- follow the camera.
local function MSUF_ShouldCrosshairFollowCamera()
    if not GetCVar then
        return false
    end

    -- 1) Klassischer Self-Highlight-Modus (Circle / Outline / Icon)
    local mode = tonumber(GetCVar("findYourselfMode") or "0") or 0
    if mode > 0 then
        return true
    end

    if GetCVarBool then
        -- ZusÃ¤tzliche Flags
        if GetCVarBool("findYourselfModeAll")
        or GetCVarBool("findYourselfModeAlways")
        or GetCVarBool("findYourselfModeCombat") then
            return true
        end
    end

    -- 2) Eigene Nameplate / Personal Resource Display
    if GetCVarBool and (GetCVarBool("nameplateShowSelf") or GetCVarBool("nameplateShowAll")) then
        return true
    end

    -- 3) Failsafe: Personal Nameplate-Frame ist sichtbar
    local personal = _G.NamePlatePersonalFrame
    if personal and personal:IsShown() then
        return true
    end

    return false
end

-- Re-anchor combat crosshair. It will only follow the camera when
-- Self Highlight / nameplates are active; otherwise we fall back to
-- the classic screen-center position.
local function MSUF_AnchorCombatCrosshair()
    if not combatCrosshairFrame then
        return
    end

    -- Default: Bildschirmmitte (altes Verhalten)
    local parent   = UIParent
    local anchorTo = UIParent
    local offsetX  = 0
    local offsetY  = -20   -- Fallback, wenn wir keine Nameplate haben

    -- Wenn Blizzard-Selfhighlight / Nameplates aktiv sind â†’ an persÃ¶nliche
    -- Nameplate hÃ¤ngen und den Offset abhÃ¤ngig vom Zoom berechnen.
    if MSUF_ShouldCrosshairFollowCamera() then
        local personal = _G.NamePlatePersonalFrame
        if personal then
            parent   = personal
            anchorTo = personal.UnitFrame or personal

            local h = personal:GetHeight() or 0

            -- Kamera-Zoom holen
            local zoom = GetCameraZoom and GetCameraZoom() or 0
            local maxFactor = tonumber(GetCVar and GetCVar("cameraDistanceMaxZoomFactor") or "1") or 1
            local maxDist = 15 * maxFactor        -- Basis-Maxdistanz in Dragonflight

            -- Normiertes "wie nah bin ich dran?"  (0 = ganz rausgezoomt, 1 = ganz nah)
            local close = 0
            if maxDist > 0 then
                close = 1 - math_min(zoom / maxDist, 1)
            end

            -- Basis-Offset: etwas unterhalb der Nameplate
            local base = h * 0.6
            -- Extra-Offset wenn wir nah dran sind (bis +60%)
            local extra = base * 0.6 * close

            offsetY = -(base + extra)
        end
    end

    -- PERF: SetPoint / SetParent only when something actually changed.
    if combatCrosshairFrame._msufAnchorParent ~= parent
        or combatCrosshairFrame._msufAnchorTo ~= anchorTo
        or combatCrosshairFrame._msufAnchorOffsetX ~= offsetX
        or combatCrosshairFrame._msufAnchorOffsetY ~= offsetY then

        combatCrosshairFrame._msufAnchorParent = parent
        combatCrosshairFrame._msufAnchorTo = anchorTo
        combatCrosshairFrame._msufAnchorOffsetX = offsetX
        combatCrosshairFrame._msufAnchorOffsetY = offsetY

        combatCrosshairFrame:ClearAllPoints()
        combatCrosshairFrame:SetParent(parent)
        combatCrosshairFrame:SetPoint("CENTER", anchorTo, "CENTER", offsetX, offsetY)
    end
end

-- Forward declaration so calls above resolve to local, not _G
local MSUF_UpdateCombatCrosshairRangeColor
local function EnsureCombatCrosshair()
    local g = EnsureGameplayDefaults()

    if not combatCrosshairFrame then
        combatCrosshairFrame = CreateFrame("Frame", "MSUF_CombatCrosshairFrame", UIParent)
        combatCrosshairFrame:SetSize(40, 40)
        MSUF_AnchorCombatCrosshair()  -- statt fixer Screen-Mitte
        combatCrosshairFrame:SetFrameStrata("BACKGROUND")
        combatCrosshairFrame:SetClampedToScreen(true)
        combatCrosshairFrame:EnableMouse(false)

        local horiz = combatCrosshairFrame:CreateTexture(nil, "ARTWORK")
        horiz:SetPoint("CENTER")

        local vert = combatCrosshairFrame:CreateTexture(nil, "ARTWORK")
        vert:SetPoint("CENTER")

        combatCrosshairFrame.horiz = horiz
        combatCrosshairFrame.vert  = vert

        combatCrosshairFrame:Hide()

        if not combatCrosshairEventFrame then
            combatCrosshairEventFrame = CreateFrame("Frame", "MSUF_CombatCrosshairEventFrame", UIParent)
            combatCrosshairEventFrame:UnregisterAllEvents()

            local function MSUF_CombatCrosshair_OnEvent(_, event, ...)
                local arg1 = ...
                local g2 = GetGameplayDBFast()
                if not g2.enableCombatCrosshair or not combatCrosshairFrame then
                    if combatCrosshairFrame then
                        combatCrosshairFrame:Hide()
                    end
                    return
                end

                local inCombat = ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false)

                if event == "PLAYER_REGEN_DISABLED" then
                    combatCrosshairFrame:Show()
                    MSUF_RequestCrosshairRangeRefresh()
                elseif event == "PLAYER_REGEN_ENABLED" then
                    combatCrosshairFrame:Hide()
                    MSUF_RequestCrosshairRangeRefresh()
                elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
                    MSUF_AnchorCombatCrosshair()
                    combatCrosshairFrame:SetShown(inCombat)
                    MSUF_RequestCrosshairRangeRefresh()
                elseif event == "NAME_PLATE_UNIT_REMOVED" and arg1 == "player" then
                    MSUF_AnchorCombatCrosshair()
                elseif event == "SPELL_RANGE_CHECK_UPDATE" then
                    MSUF_RequestCrosshairRangeRefresh()
                elseif event == "DISPLAY_SIZE_CHANGED" then
                    MSUF_AnchorCombatCrosshair()
                elseif event == "CVAR_UPDATE" then
                    local cvar = arg1
                    -- CVAR_UPDATE can fire a lot; we only care about CVars that can affect the
                    -- personal nameplate / crosshair anchor, and we coalesce rapid bursts.
                    if cvar == "nameplateShowSelf" then
                        if combatCrosshairFrame and not combatCrosshairFrame._msufAnchorPending then
                            combatCrosshairFrame._msufAnchorPending = true
                            if C_Timer_After then
                                C_Timer_After(0, function()
                                    if combatCrosshairFrame then
                                        combatCrosshairFrame._msufAnchorPending = nil
                                    end
                                    MSUF_AnchorCombatCrosshair()
                                end)
                            else
                                combatCrosshairFrame._msufAnchorPending = nil
                                MSUF_AnchorCombatCrosshair()
                            end
                        end
                    end
                end
            end

            combatCrosshairEventFrame:SetScript("OnEvent", MSUF_CombatCrosshair_OnEvent)
        end
    end

    -- Update size/thickness/colors on every call so slider changes apply immediately.
    -- PERF: only touch SetSize when the values actually changed.
    local thickness = g.crosshairThickness or 2
    if thickness < 1 then
        thickness = 1
    elseif thickness > 10 then
        thickness = 10
    end

    local size = g.crosshairSize or 40
    if size < 20 then
        size = 20
    elseif size > 80 then
        size = 80
    end

    if combatCrosshairFrame and combatCrosshairFrame._msufLastSize ~= size then
        combatCrosshairFrame._msufLastSize = size
        combatCrosshairFrame:SetSize(size, size)
    end

    if combatCrosshairFrame.horiz and combatCrosshairFrame.vert then
        if combatCrosshairFrame._msufLastThickness ~= thickness or combatCrosshairFrame._msufLastSizeForLines ~= size then
            combatCrosshairFrame._msufLastThickness = thickness
            combatCrosshairFrame._msufLastSizeForLines = size
            combatCrosshairFrame.horiz:SetSize(size, thickness)
            combatCrosshairFrame.vert:SetSize(thickness, size)
        end

        -- Apply dynamic range color (or legacy green if disabled)
        MSUF_CrosshairSyncRangeCacheFromGameplay(g)
        MSUF_UpdateCombatCrosshairRangeColor()

        -- Phase 7A: direct range-color tick (UpdateManager removed)
    if g.enableCombatCrosshairMeleeRangeColor then
        if not combatCrosshairFrame.MSUF_RangeOnUpdate then
            combatCrosshairFrame.MSUF_RangeOnUpdate = true
            combatCrosshairFrame.MSUF_RangeElapsed = 0
            combatCrosshairFrame:SetScript("OnUpdate", function(self, elapsed)
                if not self:IsShown() then return end
                local g3 = EnsureGameplayDefaults()
                if not g3.enableCombatCrosshair or not g3.enableCombatCrosshairMeleeRangeColor then
                    self:SetScript("OnUpdate", nil)
                    self.MSUF_RangeOnUpdate = nil
                    return
                end
                self.MSUF_RangeElapsed = (self.MSUF_RangeElapsed or 0) + (elapsed or 0)
                if self.MSUF_RangeElapsed < 0.15 then return end
                self.MSUF_RangeElapsed = 0
                MSUF_UpdateCombatCrosshairRangeColor()
            end)
        end
    else
        if combatCrosshairFrame.MSUF_RangeOnUpdate then
            combatCrosshairFrame:SetScript("OnUpdate", nil)
            combatCrosshairFrame.MSUF_RangeOnUpdate = nil
        end
    end

    end

    return combatCrosshairFrame
end

-- Lock / unlock helper
local function ApplyLockState()
    local g = EnsureGameplayDefaults()
    if combatFrame then
        -- Always click-through by default (never steal clicks on unitframes).
        -- When UNLOCKED, hold ALT to temporarily enable mouse so you can drag it.
        if g.lockCombatTimer then
            combatFrame:EnableMouse(false)
        else
            if IsAltKeyDown and IsAltKeyDown() then
                combatFrame:EnableMouse(true)
            else
                combatFrame:EnableMouse(false)
            end
        end
    end

    if combatStateFrame then
        if combatStateFrame._msufClickThroughActive then
            combatStateFrame:EnableMouse(false)
        elseif g.lockCombatState then
            combatStateFrame:EnableMouse(false)
        else
            combatStateFrame:EnableMouse(true)
        end
    end
end

-- Combat Timer anchor helpers
local function _MSUF_ValidateCombatTimerAnchor(v)
    if v == "player" or v == "target" or v == "focus" then
        return v
    end
    return "none"
end

local function _MSUF_GetUnitFrameForAnchor(key)
    if not key or key == "" then return nil end
    local list = _G and _G.MSUF_UnitFrames
    if list and list[key] then
        return list[key]
    end
    local gname = "MSUF_" .. key
    local f = _G and _G[gname]
    if f then
        return f
    end
    return nil
end

local function _MSUF_GetCombatTimerAnchorFrame(g)
    local key = _MSUF_ValidateCombatTimerAnchor(g and g.combatTimerAnchor)
    if key == "none" then
        return UIParent
    end
    local f = _MSUF_GetUnitFrameForAnchor(key)
    if f and f.GetCenter then
        return f
    end
    return UIParent
end

local function MSUF_Gameplay_ApplyCombatTimerAnchor(g)
    if not combatFrame then
        return
    end

    -- If the user is currently dragging the timer, do NOT re-anchor it.
    -- Re-anchoring mid-drag makes movement feel jittery (the frame fights the mouse).
    if combatFrame._msufDragging then
        return
    end

    g = g or EnsureGameplayDefaults()
    local anchor = _MSUF_GetCombatTimerAnchorFrame(g)

    combatFrame:ClearAllPoints()
    combatFrame:SetPoint("CENTER", anchor, "CENTER", tonumber(g.combatOffsetX) or 0, tonumber(g.combatOffsetY) or 0)

    -- If the user chose a unit anchor but it isn't available yet, retry once shortly after.
    local want = _MSUF_ValidateCombatTimerAnchor(g.combatTimerAnchor)
    if want ~= "none" and anchor == UIParent then
        if not combatFrame._msufAnchorRetryPending and C_Timer and C_Timer.After then
            combatFrame._msufAnchorRetryPending = true
            C_Timer.After(0.2, function()
                if combatFrame then
                    combatFrame._msufAnchorRetryPending = nil
                    MSUF_Gameplay_ApplyCombatTimerAnchor()
                end
            end)
        end
    end
end

-- Export so the main file can call this from UpdateAllFonts()
function ns.MSUF_ApplyGameplayFontFromGlobal()
    ApplyFontToCounter()
end

local function CreateCombatTimerFrame()
    if combatFrame then
        return combatFrame
    end

    local g = EnsureGameplayDefaults()

    combatFrame = CreateFrame("Frame", "MSUF_CombatTimerFrame", UIParent)
    combatFrame:SetSize(220, 60)
    MSUF_Gameplay_ApplyCombatTimerAnchor(g)
    combatFrame:SetFrameStrata("DIALOG")
    combatFrame:SetClampedToScreen(true)
    combatFrame:SetMovable(true)
    combatFrame:RegisterForDrag("LeftButton")

    combatFrame:SetScript("OnDragStart", function(self)
        local gd = EnsureGameplayDefaults()
        if gd.lockCombatTimer then
            return
        end

        -- When the timer is anchored to a unitframe, keeping the relative anchor while dragging
        -- can make the movement feel "sticky"/jittery (SetPoint fights the mouse). Detach it
        -- to UIParent for the duration of the drag, then re-attach on drag stop.
        self._msufDragging = true
        local x, y = self:GetCenter()
        if x and y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        end
        self:StartMoving()
    end)

    combatFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._msufDragging = nil
        local x, y = self:GetCenter()
        if not x or not y then
            return
        end

        local db = EnsureGameplayDefaults()
        local anchor = _MSUF_GetCombatTimerAnchorFrame(db)
        local ax, ay
        if anchor and anchor.GetCenter then
            ax, ay = anchor:GetCenter()
        end
        if not ax or not ay then
            ax, ay = UIParent:GetCenter()
        end
        if not ax or not ay then
            return
        end

        db.combatOffsetX = x - ax
        db.combatOffsetY = y - ay

        -- Re-attach to the configured anchor immediately so it stays stable.
        MSUF_Gameplay_ApplyCombatTimerAnchor(db)
    end)

    combatTimerText = combatFrame:CreateFontString(nil, "OVERLAY")
    combatTimerText:SetPoint("CENTER")

    -- very important: set font BEFORE any SetText call
    ApplyFontToCounter()
    combatTimerText:SetText("")

    -- Apply initial lock state
    ApplyLockState()


    -- Modifier listener: keep timer click-through unless ALT is held (when unlocked).
    if not ns._MSUF_CombatTimerModifierFrame then
        local f = CreateFrame("Frame")
        ns._MSUF_CombatTimerModifierFrame = f
        f:RegisterEvent("MODIFIER_STATE_CHANGED")
        f:SetScript("OnEvent", function()
            if not combatFrame then return end
            local gd = GetGameplayDBFast()
            if not gd or not gd.enableCombatTimer or gd.lockCombatTimer then
                return
            end
            if IsAltKeyDown and IsAltKeyDown() then
                combatFrame:EnableMouse(true)
            else
                combatFrame:EnableMouse(false)
            end
        end)
    end

    return combatFrame
end

------------------------------------------------------
-- Counting logic
------------------------------------------------------
------------------------------------------------------
-- Melee spell cache (for spellbook suggestions)
------------------------------------------------------
local MSUF_MeleeSpellCache
local MSUF_MeleeSpellCacheBuilt = false
local MSUF_MeleeSpellCacheBuilding = false
local MSUF_MeleeSpellCachePending = false

local function MSUF_BuildMeleeSpellCache()
    if MSUF_MeleeSpellCacheBuilt then
        return
    end
    if MSUF_MeleeSpellCacheBuilding then
        return
    end

    -- Never build suggestions in combat: defer until we leave combat to avoid stutters in raids.
    if InCombatLockdown and InCombatLockdown() then
        MSUF_MeleeSpellCachePending = true
        -- Phase 7B: one-shot EventBus callback instead of frame
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_MELEE_SPELL_CACHE", function()
                if not MSUF_MeleeSpellCachePending then return end
                MSUF_MeleeSpellCachePending = false
                if type(MSUF_EventBus_Unregister) == "function" then
                    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_MELEE_SPELL_CACHE")
                end
                MSUF_BuildMeleeSpellCache()
            end)
        end
        return
    end

    MSUF_MeleeSpellCacheBuilding = true
    MSUF_MeleeSpellCachePending = false
    MSUF_MeleeSpellCache = {}

    local seen = {}
    local maxMeleeRange = 8 -- include short melee-ish abilities (5y/6y/8y)
    local iter = 0
    local YIELD_EVERY = 250

    local function YieldMaybe()
        iter = iter + 1
        if (iter % YIELD_EVERY) == 0 then
            coroutine.yield()
        end
    end

    local function AddSpell(spellID, name, maxRange)
        if not spellID or not name or seen[spellID] then return end
        seen[spellID] = true

        local mr = tonumber(maxRange) or 0
        -- Many melee abilities report maxRange=0 even though IsSpellInRange works.
        -- Treat 0 as "melee-ish/unknown" and include it in suggestions.
        if (mr == 0) or (mr > 0 and mr <= maxMeleeRange) then
            MSUF_MeleeSpellCache[#MSUF_MeleeSpellCache + 1] = {
                id = spellID,
                name = name,
                lower = string_lower(name),
                maxRange = maxRange,
            }
        end
    end

    local function BuildBody()
        -- Preferred (Midnight/Beta+): C_SpellBook skill line scan
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo then
            local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or "spell"
            local numLines = C_SpellBook.GetNumSpellBookSkillLines()
            if type(numLines) == "number" and numLines > 0 then
                for line = 1, numLines do
                    local skillLine = { C_SpellBook.GetSpellBookSkillLineInfo(line) }
                    local offset, numItems
                    if type(skillLine[1]) == "table" then
                        offset = skillLine[1].itemIndexOffset
                        numItems = skillLine[1].numSpellBookItems
                    else
                        -- Common multi-return pattern: name, icon, itemIndexOffset, numSpellBookItems, ...
                        offset = skillLine[3]
                        numItems = skillLine[4]
                    end

                    if offset and numItems and numItems > 0 then
                        for slot = offset + 1, offset + numItems do
                            YieldMaybe()

                            local item = { C_SpellBook.GetSpellBookItemInfo(slot, bank) }
                            local itemType, spellID

                            if type(item[1]) == "table" then
                                local t = item[1]
                                itemType = t.itemType or t.spellBookItemType or t.type
                                spellID = t.spellID or t.spellId or t.actionID or t.actionId
                            else
                                itemType = item[1]
                                spellID = item[2]
                            end

                            -- Accept both string item types and Enum values
                            local isSpell = (itemType == "SPELL")
                            if not isSpell and Enum and Enum.SpellBookItemType then
                                isSpell = (itemType == Enum.SpellBookItemType.Spell)
                            end

                            if isSpell and spellID and not seen[spellID] then
                                local name
                                if C_SpellBook.GetSpellBookItemName then
                                    name = C_SpellBook.GetSpellBookItemName(slot, bank)
                                elseif GetSpellBookItemName then
                                    name = GetSpellBookItemName(slot, "spell")
                                end
                                if (not name) and GetSpellInfo then
                                    name = GetSpellInfo(spellID)
                                end

                                local maxRange
                                if C_Spell and C_Spell.GetSpellInfo then
                                    local info = C_Spell.GetSpellInfo(spellID)
                                    if info then
                                        maxRange = info.maxRange
                                    end
                                end
                                if (not maxRange) and GetSpellInfo then
                                    local _, _, _, _, _, ma = GetSpellInfo(spellID)
                                    maxRange = ma
                                end

                                if name then
                                    AddSpell(spellID, name, maxRange)
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Fallback (older clients): legacy spell tab scan
        if #MSUF_MeleeSpellCache == 0 and (GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo and GetSpellBookItemName) then
            for tab = 1, GetNumSpellTabs() do
                local _, _, offset, numSpells = GetSpellTabInfo(tab)
                if offset and numSpells then
                    for slot = offset + 1, offset + numSpells do
                        YieldMaybe()

                        local itemType, spellID = GetSpellBookItemInfo(slot, "spell")
                        if itemType == "SPELL" and spellID and not seen[spellID] then
                            local name = GetSpellBookItemName(slot, "spell")
                            if not name and GetSpellInfo then
                                name = GetSpellInfo(spellID)
                            end

                            local maxRange
                            if C_Spell and C_Spell.GetSpellInfo then
                                local info = C_Spell.GetSpellInfo(spellID)
                                if info then
                                    maxRange = info.maxRange
                                end
                            end
                            if (not maxRange) and GetSpellInfo then
                                local _, _, _, _, _, ma = GetSpellInfo(spellID)
                                maxRange = ma
                            end

                            if name then
                                AddSpell(spellID, name, maxRange)
                            end
                        end
                    end
                end
            end
        end

        if #MSUF_MeleeSpellCache > 1 then
            table_sort(MSUF_MeleeSpellCache, function(a, b)
                return a.lower < b.lower
            end)
        end
    end

    -- Chunked build via coroutine to avoid a single-frame spellbook scan spike.
    local co = coroutine.create(BuildBody)

    local function FinishBuild()
        MSUF_MeleeSpellCacheBuilding = false
        MSUF_MeleeSpellCacheBuilt = true
        MSUF_MeleeSpellCachePending = false
        -- Phase 7B: cleanup EventBus registration if any
        if type(MSUF_EventBus_Unregister) == "function" then
            MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_MELEE_SPELL_CACHE")
        end
    end

    local function Step()
        if not co then
            FinishBuild()
            return
        end

        local ok = coroutine.resume(co)
        if not ok then
            -- Fail safe: never spam errors; just mark built so we don't retry every keystroke.
            -- Suggestions will simply be empty.
            MSUF_MeleeSpellCache = MSUF_MeleeSpellCache or {}
            FinishBuild()
            return
        end

        if coroutine.status(co) == "dead" then
            FinishBuild()
            return
        end

        if C_Timer_After then
            C_Timer_After(0, Step)
        else
            -- No timer support: finish immediately (older clients)
            while coroutine.status(co) ~= "dead" do
                local ok2 = coroutine.resume(co)
                if not ok2 then break end
            end
            FinishBuild()
        end
    end

    Step()
end

-- Track which spell IDs currently have range checks enabled (base + potential override)
local MSUF_LastEnabledMeleeRangeSpellID = 0
local MSUF_LastEnabledMeleeRangeSpellID_Override = 0

local function MSUF_GetOverrideSpellID(spellID)
    if not (C_Spell and C_Spell.GetOverrideSpell) then
        return 0
    end
    local ok, overrideID = MSUF_FastCall(C_Spell.GetOverrideSpell, spellID)
    if ok and type(overrideID) == "number" and overrideID > 0 and overrideID ~= spellID then
        return overrideID
    end
    return 0
end

local function MSUF_SetEnabledMeleeRangeCheck(spellID)
    if not (C_Spell and C_Spell.EnableSpellRangeCheck) then
        return
    end

    spellID = tonumber(spellID) or 0
    local overrideID = 0
    if spellID > 0 then
        overrideID = MSUF_GetOverrideSpellID(spellID)
    end

    if spellID == MSUF_LastEnabledMeleeRangeSpellID and overrideID == MSUF_LastEnabledMeleeRangeSpellID_Override then
        return
    end

    local function Disable(id)
        if id and id > 0 then
            MSUF_FastCall(C_Spell.EnableSpellRangeCheck, id, false)
        end
    end

    local function Enable(id)
        if id and id > 0 then
            MSUF_FastCall(C_Spell.EnableSpellRangeCheck, id, true)
        end
    end

    -- Disable old checks (override first, then base)
    Disable(MSUF_LastEnabledMeleeRangeSpellID_Override)
    Disable(MSUF_LastEnabledMeleeRangeSpellID)

    MSUF_LastEnabledMeleeRangeSpellID = spellID
    MSUF_LastEnabledMeleeRangeSpellID_Override = overrideID

    -- Enable new checks
    Enable(spellID)
    Enable(overrideID)
end

local function MSUF_IsUnitInMeleeRange(unit, spellID)
    spellID = tonumber(spellID) or 0
    if spellID <= 0 then
        return false
    end
    if not (C_Spell and C_Spell.IsSpellInRange) then
        return false
    end

    -- Some specs/classes (notably DH) use override spells (e.g. Chaos Strike -> Annihilation).
    -- Try the override ID first, then fall back to the base ID.
    local overrideID = MSUF_GetOverrideSpellID(spellID)
    if overrideID and overrideID > 0 then
        local okOverride = C_Spell.IsSpellInRange(overrideID, unit)
        if okOverride == true or okOverride == 1 then
            return true
        end
    end

    local ok = C_Spell.IsSpellInRange(spellID, unit)
    -- IMPORTANT: nil = cannot be evaluated => NOT in range for the filter
    return ok == true or ok == 1
end

-- Crosshair range driver helpers (perf):
-- 1) Disable background range ticks unless we're in combat AND have a valid hostile target.
-- 2) Coalesce bursts of events (target changed / range updates) into a single refresh per frame.
MSUF_CrosshairHasValidTarget = function()
    return UnitExists and UnitExists("target")
        and UnitCanAttack and UnitCanAttack("player", "target")
        and UnitIsDeadOrGhost and (not UnitIsDeadOrGhost("target"))
end

local function MSUF_SetCrosshairRangeTaskEnabled(enabled)
    -- Phase 7A: toggle the local OnUpdate tick on combatCrosshairFrame directly
    if not combatCrosshairFrame then return end
    if enabled then
        if not combatCrosshairFrame.MSUF_RangeOnUpdate then
            combatCrosshairFrame.MSUF_RangeOnUpdate = true
            combatCrosshairFrame.MSUF_RangeElapsed = 0
            combatCrosshairFrame:SetScript("OnUpdate", function(self, elapsed)
                if not self:IsShown() then return end
                self.MSUF_RangeElapsed = (self.MSUF_RangeElapsed or 0) + (elapsed or 0)
                if self.MSUF_RangeElapsed < 0.15 then return end
                self.MSUF_RangeElapsed = 0
                MSUF_UpdateCombatCrosshairRangeColor()
            end)
        end
    else
        if combatCrosshairFrame.MSUF_RangeOnUpdate then
            combatCrosshairFrame:SetScript("OnUpdate", nil)
            combatCrosshairFrame.MSUF_RangeOnUpdate = nil
        end
    end
end

MSUF_RefreshCrosshairRangeTaskEnabled = function()
    -- Hard-disable background work unless everything is in the "fast path" state.
    if not combatCrosshairFrame or not combatCrosshairFrame.IsShown or (not combatCrosshairFrame:IsShown()) then
        MSUF_SetCrosshairRangeTaskEnabled(false)
        return
    end

    -- Keep event registration minimal: only listen for range updates when range-color is active.
    if combatCrosshairEventFrame then
        if combatCrosshairFrame._msufUseRangeColor then
            combatCrosshairEventFrame:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
        else
            combatCrosshairEventFrame:UnregisterEvent("SPELL_RANGE_CHECK_UPDATE")
        end
    end

    -- Range-color mode must be active and have a valid spell to check.
    if not combatCrosshairFrame._msufUseRangeColor or (combatCrosshairFrame._msufRangeSpellID or 0) <= 0 then
        MSUF_SetCrosshairRangeTaskEnabled(false)
        return
    end

    if not MSUF_CrosshairHasValidTarget() then
        MSUF_SetCrosshairRangeTaskEnabled(false)
        return
    end

    -- Dynamic interval: while in combat + valid target, tick fast.
    combatCrosshairFrame._msufRangeTickInterval = 0.25
    MSUF_SetCrosshairRangeTaskEnabled(true)
end

local function MSUF_RunCrosshairRangeRefresh()
    if ns then
        ns._MSUF_CrosshairRangeRefreshPending = nil
    end

    -- If the crosshair isn't visible, don't burn work; just ensure the background tick is off.
    if not combatCrosshairFrame or not combatCrosshairFrame.IsShown or (not combatCrosshairFrame:IsShown()) then
        MSUF_RefreshCrosshairRangeTaskEnabled()
        return
    end

    MSUF_UpdateCombatCrosshairRangeColor()
    MSUF_RefreshCrosshairRangeTaskEnabled()
end

MSUF_RequestCrosshairRangeRefresh = function()
    if not ns then return end
    if ns._MSUF_CrosshairRangeRefreshPending then return end
    ns._MSUF_CrosshairRangeRefreshPending = true

    if C_Timer_After then
        C_Timer_After(0, MSUF_RunCrosshairRangeRefresh)
    else
        MSUF_RunCrosshairRangeRefresh()
    end
end

-- Update combat crosshair color based on melee range to current target.
-- Uses the shared melee spell ID.
MSUF_UpdateCombatCrosshairRangeColor = function()
    if not combatCrosshairFrame or not combatCrosshairFrame.horiz or not combatCrosshairFrame.vert then
        return
    end

    -- Prefer cached flags (synced in EnsureCombatCrosshair / Apply), but remain robust if called early.
    local enabled = combatCrosshairFrame._msufCrosshairEnabled
    local useRangeColor = combatCrosshairFrame._msufUseRangeColor
    local spellID = combatCrosshairFrame._msufRangeSpellID or 0

    if enabled == nil then
        local g0 = GetGameplayDBFast()
        MSUF_CrosshairSyncRangeCacheFromGameplay(g0)
        enabled = combatCrosshairFrame._msufCrosshairEnabled
        useRangeColor = combatCrosshairFrame._msufUseRangeColor
        spellID = combatCrosshairFrame._msufRangeSpellID or 0
    end

    if not enabled then
        return
    end

    local desiredMode
    local desiredInRange = nil

    -- Default (legacy): always green
    if not useRangeColor then
        desiredMode = "alwaysGreen"
    else
        -- If we can't resolve a valid spell for range checking, don't force a "red" state.
        -- Fall back to neutral green (legacy behavior) so the crosshair isn't misleading.
        if spellID <= 0 then
            desiredMode = "alwaysGreenNoSpell"
        elseif not MSUF_CrosshairHasValidTarget() then
            -- No meaningful range state without a valid hostile target: keep the crosshair neutral (green)
            desiredMode = "alwaysGreenNoTarget"
        else
            -- PERF: enable spell range checking only when the spellID changes.
            local lastEnabled = combatCrosshairFrame._msufRangeCheckEnabledSpellID or 0
            if lastEnabled ~= spellID then
                MSUF_SetEnabledMeleeRangeCheck(spellID)
                combatCrosshairFrame._msufRangeCheckEnabledSpellID = spellID
            end

            desiredMode = "melee"
            desiredInRange = MSUF_IsUnitInMeleeRange("target", spellID)
        end
    end

    -- If we are not currently in melee-check mode, disable any previously enabled spell range check once.
    if desiredMode ~= "melee" then
        local lastEnabled = combatCrosshairFrame._msufRangeCheckEnabledSpellID or 0
        if lastEnabled > 0 then
            MSUF_SetEnabledMeleeRangeCheck(0)
            combatCrosshairFrame._msufRangeCheckEnabledSpellID = 0
        end
    end

    local lastMode = combatCrosshairFrame._msufLastRangeMode
    local lastInRange = combatCrosshairFrame._msufLastInRange

    -- PERF: only touch textures when the effective state changes.
    if desiredMode ~= lastMode or (desiredMode == "melee" and desiredInRange ~= lastInRange) then
                -- Use configured colors (default: green in-range, red out-of-range)
        local r, g, b = combatCrosshairFrame._msufInRangeR or 0, combatCrosshairFrame._msufInRangeG or 1, combatCrosshairFrame._msufInRangeB or 0
        if desiredMode == "melee" and desiredInRange == false then
            r, g, b = combatCrosshairFrame._msufOutRangeR or 1, combatCrosshairFrame._msufOutRangeG or 0, combatCrosshairFrame._msufOutRangeB or 0
        end
        combatCrosshairFrame.horiz:SetColorTexture(r, g, b, 0.9)
        combatCrosshairFrame.vert:SetColorTexture(r, g, b, 0.9)

        combatCrosshairFrame._msufLastRangeMode = desiredMode
        if desiredMode == "melee" then
            combatCrosshairFrame._msufLastInRange = desiredInRange
        else
            combatCrosshairFrame._msufLastInRange = nil
        end
    end
end
------------------------------------------------------
-- Public helpers for main addon
------------------------------------------------------

------------------------------------------------------
-- Gameplay "drivers" (perf + maintainability)
-- These functions own event registration and background tasks for each feature.
-- They make it safe to split this file later without changing behavior.
------------------------------------------------------
local function MSUF_Gameplay_ApplyCombatStateText(g)
    local wantState = (g.enableCombatStateText == true)
    local wantDance = (g.enableFirstDanceTimer == true)

    if wantState or wantDance then
        EnsureCombatStateText()

        -- "First Dance" uses a background tick (UpdateManager task) to count down the 6s window.
        -- Register the task once whenever either Combat State Text OR First Dance is enabled.
        if EnsureFirstDanceTaskRegistered then
            EnsureFirstDanceTaskRegistered()
        end

        -- If First Dance is OFF, make sure any leftover state/task is hard-stopped.
        if not wantDance then
            _StopFirstDanceTick()

        end

        -- Ensure the frame is draggable again when configuring / previewing
        MSUF_CombatState_SetClickThrough(false)

        -- Phase 7B: combat state events via EventBus
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_STATE", MSUF_CombatState_OnEvent)
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_STATE", MSUF_CombatState_OnEvent)
        end

        -- Preview while unlocked: show something so the user can position the text
        if not g.lockCombatState and combatStateText then
            if wantState then
                local enterText = g.combatStateEnterText
                if type(enterText) ~= "string" or enterText == "" then
                    enterText = "+Combat"
                end
                local er, eg, eb = MSUF_GetCombatStateColors(g)
                combatStateText._msufLastState = "enter"
                combatStateText:SetTextColor(er, eg, eb, 1)
                combatStateText:SetText(enterText)
                combatStateText:Show()
            elseif wantDance then
                local _er, _eg, _eb, lr, lg, lb = MSUF_GetCombatStateColors(g)
                combatStateText._msufLastState = "dance"
                combatStateText:SetTextColor(lr, lg, lb, 1)
                combatStateText:SetText("First Dance: 6.0")
                combatStateText:Show()
            end
        elseif combatStateText then
            -- Locked and not in an event: keep the frame hidden until real combat events fire
            combatStateText:SetText("")
            combatStateText:Hide()
        end

    else
        -- Both features disabled: hide text, unhook combat events, and hard-stop first dance
        if combatStateText then
            combatStateText:SetText("")
            combatStateText:Hide()
        end
        -- Phase 7B: unregister combat state from EventBus
        if type(MSUF_EventBus_Unregister) == "function" then
            MSUF_EventBus_Unregister("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_STATE")
            MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_STATE")
        end

        _StopFirstDanceTick()

    end
end

local function MSUF_Gameplay_ApplyCombatCrosshair(g)

    if g.enableCombatCrosshair then
        local frame = EnsureCombatCrosshair()
        -- Keep cached crosshair state in sync for fast-path ticks / conditional event registration.
        MSUF_CrosshairSyncRangeCacheFromGameplay(g)
        if combatCrosshairEventFrame then
            combatCrosshairEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            combatCrosshairEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            combatCrosshairEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            combatCrosshairEventFrame:RegisterEvent("PLAYER_LOGIN")
            -- Phase 1: PLAYER_TARGET_CHANGED via EventBus
            if type(MSUF_EventBus_Register) == "function" then
                MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_CROSSHAIR", function()
                    MSUF_RequestCrosshairRangeRefresh()
                end)
            end
            -- Only listen for range-check updates when range-color is enabled.
            if combatCrosshairFrame and combatCrosshairFrame._msufUseRangeColor then
                combatCrosshairEventFrame:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
            else
                combatCrosshairEventFrame:UnregisterEvent("SPELL_RANGE_CHECK_UPDATE")
            end
            combatCrosshairEventFrame:RegisterEvent("CVAR_UPDATE")
            combatCrosshairEventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
        end

        if frame then
            local inCombat = (InCombatLockdown and InCombatLockdown() or UnitAffectingCombat and UnitAffectingCombat("player")) or false
            frame:SetShown(inCombat)
            MSUF_RequestCrosshairRangeRefresh()
        end
    else
        if combatCrosshairEventFrame then
            combatCrosshairEventFrame:UnregisterAllEvents()
        end
        -- Phase 1: also unregister EventBus callback
        if type(MSUF_EventBus_Unregister) == "function" then
            MSUF_EventBus_Unregister("PLAYER_TARGET_CHANGED", "MSUF_CROSSHAIR")
        end

        -- Off means off: stop any range-color background task too
        MSUF_SetCrosshairRangeTaskEnabled(false)

        if combatCrosshairFrame then
            -- Ensure we do not keep any spell-range-check enabled when the crosshair is disabled.
            local lastEnabled = combatCrosshairFrame._msufRangeCheckEnabledSpellID or 0
            if lastEnabled > 0 then
                MSUF_SetEnabledMeleeRangeCheck(0)
                combatCrosshairFrame._msufRangeCheckEnabledSpellID = 0
            end
            combatCrosshairFrame:Hide()
        end
    end
end

------------------------------------------------------
-- Shaman: Player Totems tracker (player-only)
--
-- Goal: lightweight, event-driven. Only uses UpdateManager when the text needs ticking.
------------------------------------------------------
do
    local totemsFrame
    local totemSlots = {} -- [1..4] = {btn, icon, text, endTime, shown}

    local totemEventFrame
    local lastHasAnyTotem = false
    local _previewWanted = false

    local function _IsPlayerShaman()
        if UnitClass then
            local _, class = UnitClass("player")
            return class == "SHAMAN"
        end
        return false
    end

    local function _ToNumberSafe(v)
        if type(v) == "number" then
            return v
        end
        if v == nil then
            return nil
        end
        local ok, n = pcall(tonumber, v)
        if ok and type(n) == "number" then
            return n
        end
        return nil
    end
    local function _FormatRemaining(sec)
        if not sec or sec <= 0 then
            return ""
        end
        if sec < 10 then
            return string_format("%.1f", sec)
        end
        if sec < 60 then
            return string_format("%d", math.floor(sec + 0.5))
        end
        local m = math.floor(sec / 60)
        local s = math.floor(sec - (m * 60) + 0.5)
        if s >= 60 then
            m = m + 1
            s = 0
        end
        return string_format("%d:%02d", m, s)
    end

------------------------------------------------------
-- Totems preview drag positioning
-- Workflow:
-- 1) Use "Preview" to show the totem row.
-- 2) Drag the preview to place it roughly.
-- 3) Use X/Y sliders for fine tuning.
--
-- Dragging updates ONLY the stored offsets (playerTotemsOffsetX/Y).
-- It does NOT call the full Gameplay Apply path on every mouse move.
------------------------------------------------------

local function _MSUF_RoundInt(v)
    if type(v) ~= "number" then
        return 0
    end
    if v >= 0 then
        return math.floor(v + 0.5)
    end
    return math.ceil(v - 0.5)
end

local function _ApplyTotemsAnchorOnly(g, offX, offY)
    if not totemsFrame then
        return
    end

    local playerFrame = _G and _G.MSUF_player

    local anchorFrom = (g and type(g.playerTotemsAnchorFrom) == "string" and g.playerTotemsAnchorFrom ~= "") and g.playerTotemsAnchorFrom or "TOPLEFT"
    local anchorTo = (g and type(g.playerTotemsAnchorTo) == "string" and g.playerTotemsAnchorTo ~= "") and g.playerTotemsAnchorTo or "BOTTOMLEFT"

    totemsFrame:ClearAllPoints()

    local x = (type(offX) == "number") and offX or (tonumber(g and g.playerTotemsOffsetX) or 0)
    local y = (type(offY) == "number") and offY or (tonumber(g and g.playerTotemsOffsetY) or -6)

    if playerFrame then
        totemsFrame:SetPoint(anchorFrom, playerFrame, anchorTo, x, y)
    else
        totemsFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
end

local function _SetTotemsDragEnabled(on)
    if not totemsFrame then
        return
    end
    local ov = totemsFrame._msufDragOverlay
    if not ov then
        return
    end

    if on then
        ov:Show()
        ov:EnableMouse(true)
    else
        ov:EnableMouse(false)
        ov:SetScript("OnUpdate", nil)
        ov._msufDragging = nil
        ov:Hide()
    end
end

    local function _EnsureTotemsFrame()
        if totemsFrame then
            return totemsFrame
        end

        totemsFrame = CreateFrame("Frame", "MSUF_PlayerTotemsFrame", UIParent)
        totemsFrame:SetFrameStrata("MEDIUM")
        totemsFrame:SetFrameLevel(50)

        for i = 1, 4 do
            local b = CreateFrame("Frame", "MSUF_PlayerTotemSlot"..i, totemsFrame)
            b:SetSize(24, 24)

            if i == 1 then
                b:SetPoint("TOPLEFT", totemsFrame, "TOPLEFT", 0, 0)
            else
                b:SetPoint("LEFT", totemSlots[i-1].btn, "RIGHT", 4, 0)
            end

            local icon = b:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("CENTER", b, "CENTER", 0, 0)
            text:SetJustifyH("CENTER")
            text:SetJustifyV("MIDDLE")

            totemSlots[i] = {
                btn = b,
                icon = icon,
                text = text,
                endTime = 0,
                shown = false,
				-- lastText cache intentionally not used (secret-safe: never compare secret strings)
				lastText = nil,
            }

end

-- Drag overlay for Preview positioning (X/Y sliders remain for fine tuning).
if not totemsFrame._msufDragOverlay then
    local ov = CreateFrame("Button", nil, totemsFrame)
    ov:SetAllPoints(totemsFrame)
    ov:SetFrameLevel(totemsFrame:GetFrameLevel() + 200)
    ov:EnableMouse(false)
    ov:Hide()

    local hi = ov:CreateTexture(nil, "OVERLAY")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.08)
    hi:Hide()
    ov._msufHi = hi

    ov:SetScript("OnEnter", function(self)
        if self._msufHi then self._msufHi:Show() end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Totems Preview", 1, 1, 1)
            GameTooltip:AddLine("Drag to move.", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("Use X/Y offsets for fine tuning.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    ov:SetScript("OnLeave", function(self)
        if self._msufHi then self._msufHi:Hide() end
        if GameTooltip then GameTooltip:Hide() end
    end)

    ov:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end

        local g = EnsureGameplayDefaults()
        self._msufDragG = g

        local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        local cx, cy = GetCursorPosition()
        cx = cx / scale
        cy = cy / scale

        self._msufDragStartCursorX = cx
        self._msufDragStartCursorY = cy
        self._msufDragStartOffX = tonumber(g.playerTotemsOffsetX) or 0
        self._msufDragStartOffY = tonumber(g.playerTotemsOffsetY) or -6
        self._msufDragLastOffX = self._msufDragStartOffX
        self._msufDragLastOffY = self._msufDragStartOffY
        self._msufDragging = true

        self:SetScript("OnUpdate", function(self)
            if not self._msufDragging then return end
            local g = self._msufDragG
            if not g then return end

            local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            local x, y = GetCursorPosition()
            x = x / scale
            y = y / scale

            local dx = x - (self._msufDragStartCursorX or x)
            local dy = y - (self._msufDragStartCursorY or y)

            local offX = _MSUF_RoundInt((self._msufDragStartOffX or 0) + dx)
            local offY = _MSUF_RoundInt((self._msufDragStartOffY or -6) + dy)

            if offX ~= self._msufDragLastOffX or offY ~= self._msufDragLastOffY then
                self._msufDragLastOffX = offX
                self._msufDragLastOffY = offY
                g.playerTotemsOffsetX = offX
                g.playerTotemsOffsetY = offY

                _ApplyTotemsAnchorOnly(g, offX, offY)

                local opt = _G and _G.MSUF_GameplayPanel
                if opt and opt.MSUF_SyncTotemOffsetSliders then
                    opt:MSUF_SyncTotemOffsetSliders()
                end
            end
        end)
    end)

    ov:SetScript("OnMouseUp", function(self, btn)
        if btn ~= "LeftButton" then return end
        self._msufDragging = nil
        self:SetScript("OnUpdate", nil)

        local opt = _G and _G.MSUF_GameplayPanel
        if opt and opt.MSUF_SyncTotemOffsetSliders then
            opt:MSUF_SyncTotemOffsetSliders()
        end
    end)

    totemsFrame._msufDragOverlay = ov
end

totemsFrame:Hide()
        return totemsFrame
    end

    local function _ClearTotemsPreview()
        if totemsFrame then
            totemsFrame._msufPreviewActive = nil
        end
        _SetTotemsDragEnabled(false)
    end

    local function _ApplyTotemsPreview(g)
        local f = _EnsureTotemsFrame()
        f._msufPreviewActive = true
        f:Show()

        -- Static, safe preview icons (no API reads / no secret values)
        local icons = {
            "Interface\\Icons\\Spell_Nature_StoneClawTotem",
            "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02",
            "Interface\\Icons\\Spell_Nature_TremorTotem",
            "Interface\\Icons\\Spell_Nature_Windfury",
        }

        for i = 1, 4 do
            local slot = totemSlots[i]
            if slot and slot.btn then
                slot.icon:SetTexture(icons[i] or "Interface\\Icons\\INV_Misc_QuestionMark")
                if slot.icon.GetTexture and slot.icon:GetTexture() == nil then
                    slot.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
                slot.btn:Show()
                slot.shown = true

                if g and g.playerTotemsShowText then
                    local t = (i == 1 and "12s") or (i == 2 and "8s") or (i == 3 and "5s") or "3s"
                    slot.text:SetText(t)
                    slot.text:Show()
                else
                    slot.text:SetText("")
                    slot.text:Hide()
                end
            end
        end

        _SetTotemsDragEnabled(true)
    end

    local function _ApplyTotemsLayout(g)
        local f = _EnsureTotemsFrame()
        local playerFrame = _G and _G.MSUF_player

        f:ClearAllPoints()

        local anchorFrom = (type(g.playerTotemsAnchorFrom) == "string" and g.playerTotemsAnchorFrom ~= "") and g.playerTotemsAnchorFrom or "TOPLEFT"
        local anchorTo = (type(g.playerTotemsAnchorTo) == "string" and g.playerTotemsAnchorTo ~= "") and g.playerTotemsAnchorTo or "BOTTOMLEFT"

        if playerFrame then
            f:SetPoint(anchorFrom, playerFrame, anchorTo, tonumber(g.playerTotemsOffsetX) or 0, tonumber(g.playerTotemsOffsetY) or -6)
        else
            -- Fallback: still usable if unitframes are disabled / not yet created.
            f:SetPoint("CENTER", UIParent, "CENTER", tonumber(g.playerTotemsOffsetX) or 0, tonumber(g.playerTotemsOffsetY) or -6)
        end

        local size = _MSUF_Clamp(math.floor((tonumber(g.playerTotemsIconSize) or 24) + 0.5), 8, 64)
        local spacing = _MSUF_Clamp(math.floor((tonumber(g.playerTotemsSpacing) or 4) + 0.5), 0, 20)

        -- Use MSUF's global font settings (Fonts menu) so the totem countdown matches the rest of the addon.
        local fontPath = (STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF")
        local fontFlags = "OUTLINE"
        if type(_G.MSUF_GetGlobalFontSettings) == "function" then
            local p, flags = _G.MSUF_GetGlobalFontSettings()
            if type(p) == "string" and p ~= "" then
                fontPath = p
            end
            if type(flags) == "string" and flags ~= "" then
                fontFlags = flags
            end
        end
        local fontSize = _MSUF_Clamp(math.floor((tonumber(g.playerTotemsFontSize) or 14) + 0.5), 8, 64)
        if g.playerTotemsScaleTextByIconSize then
            fontSize = _MSUF_Clamp(math.floor(size * 0.55 + 0.5), 8, 64)
        end

            local tr, tg, tb = _MSUF_NormalizeRGB(g.playerTotemsTextColor, 1, 1, 1)

    -- Growth direction:
    --  RIGHT/LEFT = horizontal row
    --  UP/DOWN    = vertical column
    local growth = g.playerTotemsGrowthDirection
    if growth ~= "LEFT" and growth ~= "RIGHT" and growth ~= "UP" and growth ~= "DOWN" then
        growth = "RIGHT"
    end
    local vertical = (growth == "UP" or growth == "DOWN")

    for i = 1, 4 do
        local slot = totemSlots[i]
        if slot and slot.btn then
            slot.btn:SetSize(size, size)
            slot.text:SetFont(fontPath, fontSize, fontFlags)
            slot.text:SetTextColor(tr, tg, tb, 1)

            slot.btn:ClearAllPoints()

            if i == 1 then
                if growth == "LEFT" then
                    slot.btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
                elseif growth == "UP" then
                    slot.btn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
                elseif growth == "DOWN" then
                    slot.btn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                else -- RIGHT
                    slot.btn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                end
            else
                local prev = totemSlots[i-1] and totemSlots[i-1].btn
                if prev then
                    if growth == "LEFT" then
                        slot.btn:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
                    elseif growth == "UP" then
                        slot.btn:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
                    elseif growth == "DOWN" then
                        slot.btn:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
                    else -- RIGHT
                        slot.btn:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
                    end
                else
                    -- Fallback: should not happen, but keep stable
                    slot.btn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                end
            end
        end
    end

    if vertical then
        f:SetSize(size, (size * 4) + (spacing * 3))
    else
        f:SetSize((size * 4) + (spacing * 3), size)
    end
end

local function _FormatTotemTime(left)
    -- Midnight/Beta secret-safe:
    -- - Never directly compare/arithmetic on values that may be "secret".
    -- - Always have a simple fallback: 1 decimal seconds.
    if left == nil then
        return ""
    end

    local okSimple, simple = pcall(function()
        return string.format("%.1fs", left)
    end)
    if not okSimple then
        return ""
    end

    -- Apply nicer rules ONLY if comparisons/math are safe.
    local okNum, n = pcall(function() return tonumber(left) end)
    if not okNum or type(n) ~= "number" then
        return simple
    end

    local okLT10, isLT10 = pcall(function() return n < 10 end)
    if not okLT10 then
        return simple
    end
    if isLT10 then
        return simple
    end

    local okLT60, isLT60 = pcall(function() return n < 60 end)
    if not okLT60 then
        return simple
    end
    if isLT60 then
        local okRound, secs = pcall(function() return math.floor(n + 0.5) end)
        if okRound and type(secs) == "number" then
            return string.format("%ds", secs)
        end
        return simple
    end

    local okMS, out = pcall(function()
        local m = math.floor(n / 60)
        local s = math.floor((n - (m * 60)) + 0.5)
        if s >= 60 then
            m = m + 1
            s = 0
        end
        return string.format("%d:%02d", m, s)
    end)
    if okMS and type(out) == "string" then
        return out
    end

    return simple
end

local function _PickTotemTickInterval(minLeft)
    -- Secret-safe tick selection: only branch on numeric thresholds when safe.
    local okNum, n = pcall(function() return tonumber(minLeft) end)
    if not okNum or type(n) ~= "number" then
        return 0.50
    end

    local okLT10, isLT10 = pcall(function() return n < 10 end)
    if okLT10 and isLT10 then
        return 0.10
    end

    local okLT60, isLT60 = pcall(function() return n < 60 end)
    if okLT60 and isLT60 then
        return 0.50
    end

    return 1.00
end

local function _UpdateTotemsNow(g)
    if not totemsFrame then
        return false
    end

    local any = false
    local anyFast = false
    local anyMed = false

    for slotIndex = 1, 4 do
        local haveTotem, name, startTime, duration, icon = GetTotemInfo(slotIndex)
        local slot = totemSlots[slotIndex]

        if slot and slot.btn then
            -- Always pass-through the texture; secret values are fine to pass through.
            slot.icon:SetTexture(icon)

            local tex = slot.icon:GetTexture()
            local isActive = (tex ~= nil)

            if isActive then
                any = true

                slot.btn:Show()
                slot.icon:Show()
                slot.shown = true

                if g.playerTotemsShowText then
                    local left = GetTotemTimeLeft(slotIndex)
                    if type(left) == "number" then
                        slot.text:SetText(_FormatTotemTime(left))
                        slot.text:Show()

                        -- Step 4 tick selection without cross-slot numeric compares.
                        local hint = _PickTotemTickInterval(left)
                        if hint == 0.10 then
                            anyFast = true
                        elseif hint == 0.50 then
                            anyMed = true
                        end
                    else
                        slot.text:SetText("")
                        slot.text:Hide()
                    end
                else
                    slot.text:SetText("")
                    slot.text:Hide()
                end
            else
                slot.shown = false
                slot.text:SetText("")
                slot.text:Hide()
                slot.btn:Hide()
            end
        end
    end

    totemsFrame:SetShown(any)
    lastHasAnyTotem = any

    -- Step 4: dynamic tick (fast under 10s, slower otherwise) without secret compares.
    if anyFast then
        ns._MSUF_PlayerTotemsTickInterval = 0.10
    elseif anyMed then
        ns._MSUF_PlayerTotemsTickInterval = 0.50
    else
        ns._MSUF_PlayerTotemsTickInterval = 1.00
    end

    return any
end

local function _TickTotemText()
    local g = GetGameplayDBFast()
    if not g or not g.enablePlayerTotems or not g.playerTotemsShowText then
        return
    end

    if not totemsFrame or not totemsFrame:IsShown() then
        return
    end

    local anyFast = false
    local anyMed = false

    for i = 1, 4 do
        local slot = totemSlots[i]
        if slot and slot.shown then
            local left = GetTotemTimeLeft(i)
            if type(left) == "number" then
                slot.text:SetText(_FormatTotemTime(left))
                local hint = _PickTotemTickInterval(left)
                if hint == 0.10 then
                    anyFast = true
                elseif hint == 0.50 then
                    anyMed = true
                end
            else
                slot.text:SetText("")
            end
        end
    end

    if anyFast then
        ns._MSUF_PlayerTotemsTickInterval = 0.10
    elseif anyMed then
        ns._MSUF_PlayerTotemsTickInterval = 0.50
    else
        ns._MSUF_PlayerTotemsTickInterval = 1.00
    end
end

    local _totemTicker = nil
    local function _UpdateTotemTickEnabled(g, any)
        local enableTick = (g and g.enablePlayerTotems and g.playerTotemsShowText and any) and true or false
        if enableTick then
            if not _totemTicker and C_Timer and C_Timer.NewTicker then
                local interval = (ns._MSUF_PlayerTotemsTickInterval or 0.50)
                _totemTicker = C_Timer.NewTicker(interval, function()
                    _TickTotemText()
                end)
            end
        else
            if _totemTicker then
                _totemTicker:Cancel()
                _totemTicker = nil
            end
        end
    end

    local function _RefreshTotems()
        local g = EnsureGameplayDefaults()

        local isShaman = _IsPlayerShaman()
        if not isShaman then
            _previewWanted = false
        end

        -- Preview: Shaman-only. Works even if the feature toggle is off (positioning).
        if isShaman and _previewWanted then
            _EnsureTotemsFrame()
            _ApplyTotemsLayout(g)
            _ApplyTotemsPreview(g)
            _UpdateTotemTickEnabled(g, false)
            return
        else
            _ClearTotemsPreview()
        end

        if (not g.enablePlayerTotems) or (not isShaman) then
            _UpdateTotemTickEnabled(g, false)
            if totemsFrame then
                totemsFrame:Hide()
            end
            lastHasAnyTotem = false
            return
        end

        _EnsureTotemsFrame()
        _ApplyTotemsLayout(g)
        local any = _UpdateTotemsNow(g)
        _UpdateTotemTickEnabled(g, any)
    end

    local function _EnsureTotemEvents()
        if totemEventFrame then
            return
        end

        totemEventFrame = CreateFrame("Frame", "MSUF_PlayerTotemsEventFrame", UIParent)
        totemEventFrame:SetScript("OnEvent", function()
            _RefreshTotems()
        end)
    end

    function GameplayFeatures_PlayerTotems_Apply(g)
        -- small wrapper used by the GameplayFeatures table (defined later)
        _EnsureTotemEvents()

        totemEventFrame:UnregisterAllEvents()
        if g and g.enablePlayerTotems and _IsPlayerShaman() then
            -- Totems change is best covered by PLAYER_TOTEM_UPDATE. Also refresh on login/world.
            totemEventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
            totemEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            totemEventFrame:RegisterEvent("PLAYER_LOGIN")
        end

        _RefreshTotems()
    end

    -- Public escape hatch: Options / other modules can force a refresh without poking locals.
    _G.MSUF_PlayerTotems_ForceRefresh = _RefreshTotems

    function ns.MSUF_PlayerTotems_TogglePreview()
        _previewWanted = not _previewWanted
        _RefreshTotems()
    end

    function ns.MSUF_PlayerTotems_IsPreviewActive()
        return (_previewWanted and true) or false
    end

end



------------------------------------------------------
-- Party Interrupt Tracker (Kick tracker)
-- Event-driven; ticker only while any cooldown is active.
-- SpellID laundering uses a hidden StatusBar (MIT-style) to remain 12.0-safe.
------------------------------------------------------
local GameplayFeatures_KickTracker_Apply
do
    local CreateFrame = CreateFrame
    local UIParent = UIParent
    local GetTime = GetTime
    local IsInInstance = IsInInstance
    local IsInGroup = IsInGroup
    local IsInRaid = IsInRaid
    local UnitExists = UnitExists
    local UnitName = UnitName
    local UnitClass = UnitClass
    local UnitGUID = UnitGUID
    local IsSpellKnown = IsSpellKnown
    local pcall = pcall
    local floor = math.floor
    local format = string.format

local KT_ALL_INTERRUPTS = {
    [6552]   = { name = "Pummel",            cd = 15, icon = 132938 },
    [1766]   = { name = "Kick",              cd = 15, icon = 132219 },
    [2139]   = { name = "Counterspell",      cd = 24, icon = 135856 },
    [57994]  = { name = "Wind Shear",        cd = 12, icon = 136018 },
    [106839] = { name = "Skull Bash",        cd = 15, icon = 236946 },
    [78675]  = { name = "Solar Beam",        cd = 60, icon = 236748 },
    [47528]  = { name = "Mind Freeze",       cd = 15, icon = 237527 },
    [96231]  = { name = "Rebuke",            cd = 15, icon = 523893 },
    [183752] = { name = "Disrupt",           cd = 15, icon = 1305153 },
    [116705] = { name = "Spear Hand Strike", cd = 15, icon = 608940 },
    [15487]  = { name = "Silence",           cd = 45, icon = 458230 },
    [147362] = { name = "Counter Shot",      cd = 24, icon = 249170 },
    [187707] = { name = "Muzzle",            cd = 15, icon = 1376045 },
    [19647]  = { name = "Spell Lock",        cd = 24, icon = 136174 },
    [132409] = { name = "Spell Lock",        cd = 24, icon = 136174 },
    [119914] = { name = "Axe Toss",          cd = 30, icon = "Interface\\Icons\\ability_warrior_titansgrip" },
    [1276467] = { name = "Fel Ravager",      cd = 25, icon = "Interface\\Icons\\spell_shadow_summonfelhunter" },
    [351338] = { name = "Quell",             cd = 20, icon = 4622469 },
}

    local KT_CLASS_INTERRUPT_LIST = {
    WARRIOR     = { 6552 },
    ROGUE       = { 1766 },
    MAGE        = { 2139 },
    SHAMAN      = { 57994 },
    DRUID       = { 106839, 78675 },           -- Skull Bash (feral/guardian), Solar Beam (balance)
    DEATHKNIGHT = { 47528 },
    PALADIN     = { 96231 },
    DEMONHUNTER = { 183752 },
    MONK        = { 116705 },
    PRIEST      = { 15487 },                    -- Silence (shadow only)
    HUNTER      = { 147362, 187707 },           -- Counter Shot (BM/MM), Muzzle (survival)
    WARLOCK     = { 19647, 132409, 119914 },
    EVOKER      = { 351338 },
}

-- Class colors: use MSUF's customizable class color table (Colors menu) when present.
-- Cached + invalidated on Gameplay Apply to ensure live updates when the user edits class colors.
local ktClassColorCache = {}
local ktClassColorGen = 1

local function KT_BumpClassColorGen()
    ktClassColorGen = ktClassColorGen + 1
    for k in pairs(ktClassColorCache) do
        ktClassColorCache[k] = nil
    end
end

local function KT_GetClassColor(classToken)
    if not classToken then
        return 1, 1, 1
    end

    local hit = ktClassColorCache[classToken]
    if hit then
        return hit[1], hit[2], hit[3]
    end

    local r, g, b

    -- Prefer MSUF's custom class colors (Colors > Class bar colors).
    local db = _G and _G.MSUF_DB or MSUF_DB
    if db and type(db.classColors) == "table" then
        local t = db.classColors[classToken]
        if type(t) == "table" and type(t.r) == "number" and type(t.g) == "number" and type(t.b) == "number" then
            r, g, b = t.r, t.g, t.b
        elseif type(t) == "string" and type(_G) == "table" and type(_G.MSUF_FONT_COLORS) == "table" and type(_G.MSUF_FONT_COLORS[t]) == "table" then
            local c = _G.MSUF_FONT_COLORS[t]
            r, g, b = c[1], c[2], c[3]
        end
    end

    if r == nil then
        local c = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]) or nil
        if c then
            r, g, b = c.r, c.g, c.b
        end
    end

    if r == nil and C_ClassColor and C_ClassColor.GetClassColor then
        local ccObj = C_ClassColor.GetClassColor(classToken)
        if ccObj and ccObj.GetRGB then
            r, g, b = ccObj:GetRGB()
        end
    end

    r, g, b = r or 1, g or 1, b or 1
    ktClassColorCache[classToken] = { r, g, b }
    return r, g, b
end

-- Preview mode (when unlocked): show dummy names + running dummy timers so you can move/size the tracker.
local KT_PREVIEW_NAMES = {
    "Dummy Rogue",
    "Dummy Mage",
    "Dummy Warrior",
    "Dummy Demon Hunter",
    "Dummy Monk",
}
local KT_PREVIEW_CLASSES = { "ROGUE", "MAGE", "WARRIOR", "DEMONHUNTER", "MONK" }
local KT_PREVIEW_INTERRUPTS = { 1766, 2139, 6552, 183752, 116705 } -- Kick/CS/Pummel/Disrupt/Spear Hand


    local ktFrame, ktEventFrame, ktTicker, ktCastFrames
    local ktActive = false
    local ktPreview = false
    
    -- Lightweight MSUF<->MSUF party sync (addon messages)
    -- Only active while the tracker is active in Mythic+ (and NOT in preview mode).
    local KT_SYNC_PREFIX = "MSUF_KT1"
    local ktSyncFrame
    local ktSyncRegistered = false
    local ktSyncHelloSent = false
    local ktSyncPeers = 0

    local function KT_SyncGetChannel()
        if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            return "INSTANCE_CHAT"
        end
        return "PARTY"
    end

    local function KT_SyncEnsure()
        if ktSyncRegistered then return end
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            -- Safe: runs only on activation (never in hot paths).
            C_ChatInfo.RegisterAddonMessagePrefix(KT_SYNC_PREFIX)
        end

        ktSyncFrame = ktSyncFrame or CreateFrame("Frame")
        ktSyncFrame:UnregisterAllEvents()
        ktSyncFrame:RegisterEvent("CHAT_MSG_ADDON")
        ktSyncFrame:SetScript("OnEvent", function(self, event, prefix, msg, channel, sender)
            if prefix ~= KT_SYNC_PREFIX or type(msg) ~= "string" then
                return
            end

            -- Format:
            --   H                    (hello)
            --   A                    (ack)
            --   K;<guid>;<spellID>;<cd>
            local t, a, b, c = strsplit(";", msg)
            if t == "H" then
                if C_ChatInfo and C_ChatInfo.SendAddonMessage then
                    C_ChatInfo.SendAddonMessage(KT_SYNC_PREFIX, "A", KT_SyncGetChannel())
                end
                return
            elseif t == "A" then
                ktSyncPeers = (ktSyncPeers or 0) + 1
                return
            elseif t == "K" then
                local guid = a
                local spellID = tonumber(b)
                local cd = tonumber(c)
                if not guid or not spellID or not cd then
                    return
                end
                if not ktActive or ktPreview then
                    return
                end
                local g = GetGameplayDBFast()
                if not g or not g.enableKickTracker then
                    return
                end
                local idx = ktGuidToIndex and ktGuidToIndex[guid]
                if not idx then
                    return
                end
                local row = ktRows and ktRows[idx]
                if not row then
                    return
                end

                row.interruptID = spellID
                row.readyAt = GetTime() + cd
                KT_UpdateVisuals(g)
                return
            end
        end)

        ktSyncRegistered = true
    end

    local function KT_SyncStop()
        if ktSyncFrame then
            ktSyncFrame:UnregisterAllEvents()
            ktSyncFrame:SetScript("OnEvent", nil)
        end
        ktSyncRegistered = false
        ktSyncHelloSent = false
        ktSyncPeers = 0
    end

    local function KT_SyncHello()
        if ktSyncHelloSent then return end
        ktSyncHelloSent = true
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then
            C_ChatInfo.SendAddonMessage(KT_SYNC_PREFIX, "H", KT_SyncGetChannel())
        end
    end

    local function KT_SyncSendKick(guid, spellID, cd)
        if not guid or not spellID or not cd then return end
        if not ktActive or ktPreview then return end
        if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
        local msg = "K;" .. guid .. ";" .. tostring(spellID) .. ";" .. tostring(cd)
        C_ChatInfo.SendAddonMessage(KT_SYNC_PREFIX, msg, KT_SyncGetChannel())
    end

    local ktRows = {}
    local ktUnitToIndex = {}
    local ktPetToOwner = {}
    local ktRosterUnits = { "player" }

    local ktWasher, ktWashedValue
    local ktIsInterruptCache = {}

    local KT_RegisterCastFramesForRoster

    local function KT_EnsureWasher()
        if ktWasher then return end
        ktWasher = CreateFrame("StatusBar", nil, UIParent)
        ktWasher:Hide()
        ktWasher:SetMinMaxValues(0, 2000000)
        ktWasher:SetValue(0)
        ktWasher:SetScript("OnValueChanged", function(_, v)
            ktWashedValue = v
        end)
    end

    local function KT_LaunderSpellID(raw)
        if raw == nil then return nil end
        KT_EnsureWasher()
        ktWashedValue = nil

        -- The SetValue->OnValueChanged path "launders" the incoming param into a safe number.
        -- Must be protected: in 12.0 some event args can be secret/tainted and crash SetValue.
        ktWasher:SetValue(0)
        pcall(ktWasher.SetValue, ktWasher, raw)

        local v = ktWashedValue
        if type(v) ~= "number" then
            return nil
        end
        return v
    end

    local function KT_IsInterruptID(id)
        local cached = ktIsInterruptCache[id]
        if cached ~= nil then
            return cached
        end
        local ok, data = pcall(function()
            return KT_ALL_INTERRUPTS[id]
        end)
        cached = (ok and data ~= nil) and true or false
        ktIsInterruptCache[id] = cached
        return cached
    end

    local function KT_GetInterruptData(id)
        return KT_ALL_INTERRUPTS[id]
    end

    local function KT_FormatRemaining(sec)
        if sec <= 0 then return "0" end
        if sec >= 60 then
            local m = floor(sec / 60)
            local s = floor(sec - (m * 60))
            return format("%d:%02d", m, s)
        end
        return tostring(floor(sec + 0.5))
    end

        local function KT_ShouldShow(g)
            -- Active in any 5-man dungeon instance (instType == 'party').
            -- Keeps overhead near-zero outside dungeons: no unit events, no tickers, no UI.
            if not g or not g.enableKickTracker then
                return false
            end
    
            -- Never show in raids.
            if IsInRaid() then
                return false
            end
    
            local inInstance, instType = IsInInstance()
            if not inInstance or instType ~= 'party' then
                return false
            end
    
            -- Respect the existing toggle if present (defaults to true).
            if g.kickTrackerShowInDungeon == false then
                return false
            end
    
            return true
        end


    local function KT_EnsureFrame()
        if ktFrame then return ktFrame end

        local f = CreateFrame("Frame", "MSUF_KickTrackerFrame", UIParent)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")

        f:SetScript("OnDragStart", function(self)
            local g = EnsureGameplayDefaults()
            if g.lockKickTracker then return end
            self:StartMoving()
        end)

        f:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local g = EnsureGameplayDefaults()
            local cx, cy = self:GetCenter()
            local px, py = UIParent:GetCenter()
            if cx and cy and px and py then
                g.kickTrackerOffsetX = cx - px
                g.kickTrackerOffsetY = cy - py
            end
        end)

        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.35)
        f.bg = bg

        for i = 1, 5 do
            local row = CreateFrame("Frame", nil, f)

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetColorTexture(0, 0, 0, 0.20)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.nameText:SetJustifyH("LEFT")

            row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.timeText:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.timeText:SetJustifyH("RIGHT")

            row.unit = nil
            row.guid = nil
            row.name = nil
            row.class = nil
            row.interruptID = nil
            row.readyAt = 0

            ktRows[i] = row
        end

        ktFrame = f
        return f
    end

    local function KT_StopTicker()
        if ktTicker then
            ktTicker:Cancel()
            ktTicker = nil
        end
    end

    local function KT_ApplyPoint(g)
        KT_SyncEnsure()
        KT_SyncHello()

        local f = KT_EnsureFrame()
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", g.kickTrackerOffsetX or 0, g.kickTrackerOffsetY or -140)
    end

    local function KT_ApplyLayout(g)
        local f = KT_EnsureFrame()

        local w = g.kickTrackerWidth or 220
        local iconSize = g.kickTrackerIconSize or 26
        local spacing = g.kickTrackerSpacing or 4
        local fontSize = g.kickTrackerFontSize or 14
        local showNames = g.kickTrackerShowNames and true or false
        local bgAlpha = tonumber(g.kickTrackerBgAlpha) or 0.35
        bgAlpha = _MSUF_Clamp(bgAlpha, 0, 1)
        local rowBgAlpha = _MSUF_Clamp(bgAlpha * 0.57, 0, 1)

        if f._msuf_w == w and f._msuf_icon == iconSize and f._msuf_spacing == spacing and f._msuf_font == fontSize and f._msuf_showNames == showNames and f._msuf_bgAlpha == bgAlpha then
            return
        end
        f._msuf_w = w
        f._msuf_icon = iconSize
        f._msuf_spacing = spacing
        f._msuf_font = fontSize
        f._msuf_showNames = showNames

        f._msuf_bgAlpha = bgAlpha

        if f.bg then
            f.bg:SetColorTexture(0, 0, 0, bgAlpha)
        end
        f:SetWidth(w)

        local padX, padY = 6, 6
        local rowW = w - (padX * 2)
        local rowH = iconSize

        local fontPath, fontFlags, cr, cg, cb = GetGameplayFontSettings()

        for i = 1, 5 do
            local row = ktRows[i]
            row:SetWidth(rowW)
            row:SetHeight(rowH)
            if row.bg then
                row.bg:SetColorTexture(0, 0, 0, rowBgAlpha)
            end
            row:ClearAllPoints()

            if i == 1 then
                row:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -padY)
            else
                row:SetPoint("TOPLEFT", ktRows[i - 1], "BOTTOMLEFT", 0, -spacing)
            end

            row.icon:SetSize(iconSize, iconSize)

            if showNames then
                row.nameText:Show()
                row.timeText:ClearAllPoints()
                row.timeText:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            else
                row.nameText:Hide()
                row.timeText:ClearAllPoints()
                row.timeText:SetPoint("CENTER", row, "CENTER", 0, 0)
            end

            if fontPath then
                row.nameText:SetFont(fontPath, fontSize, fontFlags or "")
                row.timeText:SetFont(fontPath, fontSize, fontFlags or "")
            end
            if cr then
                -- Match Gameplay font color for the timer text; names use class colors.
                row.timeText:SetTextColor(cr, cg, cb)
            end
        end

        local height = (padY * 2) + (rowH * 5) + (spacing * 4)
        f:SetHeight(height)
    end

    local function KT_RebuildMappings()
        for k in pairs(ktUnitToIndex) do ktUnitToIndex[k] = nil end
        for k in pairs(ktPetToOwner) do ktPetToOwner[k] = nil end

        for i = 1, 5 do
            local row = ktRows[i]
            local unit = row.unit
            if unit then
                ktUnitToIndex[unit] = i

                if unit == "player" then
                    ktPetToOwner["pet"] = "player"
                elseif unit:sub(1, 5) == "party" then
                    local n = unit:sub(6)
                    if n and n ~= "" then
                        ktPetToOwner["partypet" .. n] = unit
                    end
                elseif unit:sub(1, 4) == "raid" then
                    local n = unit:sub(5)
                    if n and n ~= "" then
                        ktPetToOwner["raidpet" .. n] = unit
                    end
                end
            end
        end
    end

    local function KT_PickDefaultInterruptID(unit, classTag)
        if not classTag then return nil end
        local list = KT_CLASS_INTERRUPT_LIST[classTag]
        if not list then return nil end

        -- For the player we can be accurate by checking IsSpellKnown().
        if unit == "player" and IsSpellKnown then
            for i = 1, #list do
                local id = list[i]
                if id and IsSpellKnown(id) then
                    return id
                end
            end
        end

        return list[1]
    end

    local function KT_SetRowVisual(row, now, g)
        local id = row.interruptID
        local data = id and KT_GetInterruptData(id)

        if data and data.icon then
            row.icon:SetTexture(data.icon)
        else
            row.icon:SetTexture(nil)
        end

        local name = row.name or ""
        row.nameText:SetText(name)

        local classToken = row.class
if classToken then
    -- Avoid repeated lookups per-tick: only recompute when class changes or colors were invalidated.
    if row._msuf_colorGen ~= ktClassColorGen or row._msuf_lastClass ~= classToken then
        local r, g, b = KT_GetClassColor(classToken)
        row._msuf_lastClass = classToken
        row._msuf_colorGen = ktClassColorGen
        row._msuf_nameR, row._msuf_nameG, row._msuf_nameB = r, g, b
    end
    row.nameText:SetTextColor(row._msuf_nameR or 1, row._msuf_nameG or 1, row._msuf_nameB or 1)
else
    row.nameText:SetTextColor(1, 1, 1)
end

        local remaining = (row.readyAt or 0) - now
        if remaining > 0.05 then
            row.timeText:SetText(KT_FormatRemaining(remaining))
            return true
        end

        row.readyAt = 0
        if g.kickTrackerShowReady then
            row.timeText:SetText("READY")
        else
            row.timeText:SetText("")
        end
        return false
    end

    local function KT_UpdateVisuals(g)
        if not ktFrame then return end
        if not ktFrame:IsShown() then
            KT_StopTicker()
            return
        end

        local now = GetTime()
        local anyActive = false



if ktPreview then
    -- Ensure dummy data and keep timers running.
    for i = 1, 5 do
        local row = ktRows[i]
        row:Show()
        row.unit = nil
        row.guid = nil

        if not row._msuf_previewInited then
            row._msuf_previewInited = true
            row.name = KT_PREVIEW_NAMES[i] or ("Dummy " .. i)
            row.class = KT_PREVIEW_CLASSES[i]
            row.interruptID = KT_PREVIEW_INTERRUPTS[i] or 1766
            -- Staggered initial remaining time so the list "moves" immediately.
            row.readyAt = now + (2 + (i * 2.5))
        end

        -- When a timer completes, restart it with the real CD (if known) to keep it cycling.
        if not row.readyAt or (row.readyAt - now) <= 0.05 then
            local data = KT_GetInterruptData(row.interruptID)
            local cd = (data and data.cd) or (12 + (i * 2))
            row.readyAt = now + cd
        end

        if KT_SetRowVisual(row, now, g) then
            anyActive = true
        end
    end

    if anyActive then
        if not ktTicker then
            ktTicker = C_Timer.NewTicker(0.20, function()
                local g = EnsureGameplayDefaults()
                if not g.enableKickTracker or not ktFrame or not ktFrame:IsShown() or not ktActive then
                    KT_StopTicker()
                    return
                end
                KT_UpdateVisuals(g)
            end)
        end
    else
        KT_StopTicker()
    end
    return
end
        for i = 1, 5 do
            local row = ktRows[i]
            local unit = row.unit

            if unit and UnitExists(unit) then
                row:Show()
                if KT_SetRowVisual(row, now, g) then
                    anyActive = true
                end
            else
                row:Hide()
            end
        end

        if anyActive then
            if not ktTicker then
                ktTicker = C_Timer.NewTicker(0.20, function()
                    local g = EnsureGameplayDefaults()
                    if not g.enableKickTracker or not ktFrame or not ktFrame:IsShown() or not ktActive then
                        KT_StopTicker()
                        return
                    end
                    KT_UpdateVisuals(g)
                end)
            end
        else
            KT_StopTicker()
        end
    end

    local function KT_UpdateRoster(g)
        KT_EnsureFrame()

        local units = ktRosterUnits
        units[1] = "player"
        units[2], units[3], units[4], units[5] = nil, nil, nil, nil

        if IsInGroup() and not IsInRaid() then
            for i = 1, 4 do
                local u = "party" .. i
                if UnitExists(u) then
                    units[i + 1] = u
                end
            end
        elseif IsInRaid() and g.kickTrackerShowInRaid then
            local myGuid = UnitGUID("player")
            local n = 1
            for i = 1, 40 do
                local u = "raid" .. i
                if UnitExists(u) then
                    local guid = UnitGUID(u)
                    if guid and guid ~= myGuid then
                        n = n + 1
                        units[n] = u
                        if n >= 5 then break end
                    end
                end
            end
        end

        for i = 1, 5 do
            local row = ktRows[i]
            local unit = units[i]

            row.unit = unit
            row.guid = nil
            row.name = nil
            row.class = nil

            if unit and UnitExists(unit) then
                row.guid = UnitGUID(unit)
                row.name = UnitName(unit) or unit
                local _, classTag = UnitClass(unit)
                row.class = classTag

                if not row.interruptID then
                    row.interruptID = KT_PickDefaultInterruptID(unit, classTag)
                end
            else
                row.readyAt = 0
            end
        end

        KT_RebuildMappings()
        KT_RegisterCastFramesForRoster()
        KT_UpdateVisuals(g)
    end

    local function KT_OnSpellSucceeded(unit, rawSpellID)
        if not unit then return end

        local ownerUnit = ktPetToOwner[unit] or unit
        local idx = ktUnitToIndex[ownerUnit]
        if not idx then
            return
        end

        local spellID = KT_LaunderSpellID(rawSpellID)
        if not spellID then
            return
        end

        if not KT_IsInterruptID(spellID) then
            return
        end

        local row = ktRows[idx]
        if not row then return end

        local data = KT_GetInterruptData(spellID)
        if not data or not data.cd then
            return
        end

        row.interruptID = spellID
        row.readyAt = GetTime() + data.cd
        KT_SyncSendKick(row.guid, spellID, data.cd)

        local g = EnsureGameplayDefaults()
        KT_UpdateVisuals(g)
    end


    -- In 12.0, UNIT_SPELLCAST_SUCCEEDED is a UNIT EVENT and may not fire unless registered via RegisterUnitEvent.
    -- To keep it performant and reliable, we maintain 5 tiny cast frames that are re-registered whenever the roster changes.
    local function KT_EnsureCastFrames()
        if ktCastFrames then return end
        ktCastFrames = {}
        for i = 1, 5 do
            local cf = CreateFrame("Frame")
            cf:SetScript("OnEvent", function(_, _, unit, _, spellID)
                local g = EnsureGameplayDefaults()
                if not g.enableKickTracker or not ktActive then return end
                if not ktFrame or not ktFrame:IsShown() then return end
                KT_OnSpellSucceeded(unit, spellID)
            end)
            ktCastFrames[i] = cf
        end
    end

    local function KT_UnregisterCastFrames()
        if not ktCastFrames then return end
        for i = 1, 5 do
            local cf = ktCastFrames[i]
            if cf then
                cf:UnregisterAllEvents()
            end
        end
    end

    KT_RegisterCastFramesForRoster = function()
        KT_EnsureCastFrames()
        -- Re-register per slot (unit + its pet) to guarantee we get SUCCEEDED events in 12.0.
        for i = 1, 5 do
            local cf = ktCastFrames[i]
            if cf then
                cf:UnregisterAllEvents()
                local unit = ktRows[i] and ktRows[i].unit
                if unit and UnitExists(unit) then
                    if cf.RegisterUnitEvent then
                        if unit == "player" then
                            cf:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
                        elseif unit:sub(1, 5) == "party" then
                            local n = unit:sub(6)
                            local pet = (n and n ~= "") and ("partypet" .. n) or nil
                            if pet and UnitExists(pet) then
                                cf:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit, pet)
                            else
                                cf:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
                            end
                        elseif unit:sub(1, 4) == "raid" then
                            local n = unit:sub(5)
                            local pet = (n and n ~= "") and ("raidpet" .. n) or nil
                            if pet and UnitExists(pet) then
                                cf:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit, pet)
                            else
                                cf:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
                            end
                        else
                            cf:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
                        end
                    else
                        -- Fallback (older builds): broad register and filter inside KT_OnSpellSucceeded.
                        cf:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                    end
                end
            end
        end
    end

    local function KT_EnsureEvents()
        if ktEventFrame then return end
        ktEventFrame = CreateFrame("Frame")
        ktEventFrame:SetScript("OnEvent", function(_, event, ...)
            local g = EnsureGameplayDefaults()
            if not g.enableKickTracker then
                return
            end

            -- While active we handle roster/pet changes; otherwise we only react to instance/challenge transitions.
            if event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
                if not ktActive then return end
                KT_UpdateRoster(g)
                return
            end

            local shouldShow = KT_ShouldShow(g)
            if not shouldShow then
                if ktActive then
                    ktActive = false
                    -- Stop roster listeners while inactive (0 overhead outside M+).
                    ktEventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
                    ktEventFrame:UnregisterEvent("UNIT_PET")
                end
                if ktFrame then ktFrame:Hide() end
                KT_StopTicker()
                KT_UnregisterCastFrames()
                    KT_SyncStop()
                    return
            end

            -- Becoming (or staying) active.
            if not ktActive then
                ktActive = true
                ktEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
                ktEventFrame:RegisterEvent("UNIT_PET")
            end

            KT_SyncEnsure()
            KT_SyncHello()

            local f = KT_EnsureFrame()
            f:Show()
            KT_ApplyPoint(g)
            KT_ApplyLayout(g)
            KT_UpdateRoster(g)
        end)
    end

    local function KT_RegisterEvents()
        KT_EnsureEvents()
        ktEventFrame:UnregisterAllEvents()
        -- Minimal watchers. Roster/pet events are registered only while active.
        ktEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        ktEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    end

    local function KT_UnregisterEvents()
        if ktEventFrame then
            ktEventFrame:UnregisterAllEvents()
        end
        KT_UnregisterCastFrames()
        KT_SyncStop()
    end

    local function KT_Apply(g)
        if not g or not g.enableKickTracker then
            ktActive = false
            
            ktPreview = false
if ktEventFrame then
                ktEventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
                ktEventFrame:UnregisterEvent("UNIT_PET")
            end
            if ktFrame then ktFrame:Hide() end
            KT_StopTicker()
            KT_UnregisterEvents()
            return
        end

        KT_RegisterEvents()



        -- Class colors may have changed via Colors menu; invalidate cache so rows pick up the latest.
        KT_BumpClassColorGen()

-- Preview mode when unlocked: show dummy rows so the frame can be positioned anywhere.
-- This intentionally overrides real tracking while unlocked (stable preview UX).
if not g.lockKickTracker then
    ktPreview = true
    ktActive = true

    -- No backend listeners while previewing (zero gameplay overhead; only the preview ticker runs).
    if ktEventFrame then
        ktEventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
        ktEventFrame:UnregisterEvent("UNIT_PET")
    end
    KT_UnregisterCastFrames()
    KT_SyncStop()

    local f = KT_EnsureFrame()
    f:Show()
    KT_ApplyPoint(g)
    KT_ApplyLayout(g)

    -- Reset preview init so layout changes reflect immediately.
    for i = 1, 5 do
        local row = ktRows[i]
        row._msuf_previewInited = nil
    end

    KT_UpdateVisuals(g)
    return
end

ktPreview = false
        local shouldShow = KT_ShouldShow(g)
        if not shouldShow then
            ktActive = false
            
            ktPreview = false
if ktEventFrame then
                ktEventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
                ktEventFrame:UnregisterEvent("UNIT_PET")
            end
            if ktFrame then ktFrame:Hide() end
            KT_StopTicker()
            KT_UnregisterCastFrames()
            KT_SyncStop()
            return
        end

                ktPreview = false

        -- Active in Mythic+ now.
        if not ktActive then
            ktActive = true
            if ktEventFrame then
                ktEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
                ktEventFrame:RegisterEvent("UNIT_PET")
            end
        end

        local f = KT_EnsureFrame()
        f:Show()
        KT_ApplyPoint(g)
        KT_ApplyLayout(g)
        KT_UpdateRoster(g)
    end

    GameplayFeatures_KickTracker_Apply = function(g)
        KT_Apply(g)
    end
end

-- Feature tables (single-file modules) for readability and safer future refactors
local GameplayFeatures = {
    CombatTimer     = {},
    CombatStateText = {},
    CombatCrosshair = {},
    PlayerTotems    = {},
    KickTracker     = {},
}

function GameplayFeatures.CombatTimer.Apply(g)
    if g.enableCombatTimer and not combatFrame then
        CreateCombatTimerFrame()
    end

    -- Update font whenever visuals are (re)applied
    ApplyFontToCounter()
    -- Ensure lock state is applied too
    ApplyLockState()
    if combatFrame then
        MSUF_Gameplay_ApplyCombatTimerAnchor(g)
        combatFrame:SetShown(g.enableCombatTimer)
    end
end

GameplayFeatures.CombatStateText.Apply = MSUF_Gameplay_ApplyCombatStateText
GameplayFeatures.CombatCrosshair.Apply = MSUF_Gameplay_ApplyCombatCrosshair

GameplayFeatures.PlayerTotems.Apply = GameplayFeatures_PlayerTotems_Apply
    GameplayFeatures.KickTracker.Apply = GameplayFeatures_KickTracker_Apply

local GameplayFeatureOrder = {"CombatTimer", "CombatStateText", "CombatCrosshair", "PlayerTotems", "KickTracker" }

local function Gameplay_ApplyAllFeatures(g)
    for i = 1, #GameplayFeatureOrder do
        local key = GameplayFeatureOrder[i]
        local f = GameplayFeatures[key]
        if f and f.Apply then
            f.Apply(g)
        end
    end
end

function ns.MSUF_RequestGameplayApply()
    local g = EnsureGameplayDefaults()

    Gameplay_ApplyAllFeatures(g)

-- Phase 7A: combat-timer tick — event-driven start/stop (no permanent ticker)
    local function _StartCombatTimerTick()
        if ns._MSUF_CombatTimerTicker then return end  -- already running
        if C_Timer and C_Timer.NewTicker then
            ns._MSUF_CombatTimerTicker = C_Timer.NewTicker(1.0, function()
                MSUF_Gameplay_TickCombatTimer()
            end)
        end
    end
    local function _StopCombatTimerTick()
        if ns._MSUF_CombatTimerTicker then
            ns._MSUF_CombatTimerTicker:Cancel()
            ns._MSUF_CombatTimerTicker = nil
        end
    end

    -- Phase 7B: combat timer events via EventBus (frame eliminated)
    local function _CombatTimer_OnRegenDisabled()
        local gd = GetGameplayDBFast()
        if not gd or not gd.enableCombatTimer then return end
        combatStartTime = GetTime()
        wasInCombat = true
        lastTimerText = ""
        MSUF_Gameplay_TickCombatTimer()
        _StartCombatTimerTick()
    end
    local function _CombatTimer_OnRegenEnabled()
        local gd = GetGameplayDBFast()
        if not gd or not gd.enableCombatTimer then return end
        _StopCombatTimerTick()
        wasInCombat = false
        combatStartTime = nil
        lastTimerText = ""
        MSUF_Gameplay_TickCombatTimer()
    end
    local function _CombatTimer_OnPEW()
        local gd = GetGameplayDBFast()
        if not gd or not gd.enableCombatTimer then return end
        lastTimerText = ""
        if UnitAffectingCombat and UnitAffectingCombat("player") then
            if not combatStartTime then
                combatStartTime = GetTime()
            end
            wasInCombat = true
            MSUF_Gameplay_TickCombatTimer()
            _StartCombatTimerTick()
        else
            _StopCombatTimerTick()
            wasInCombat = false
            combatStartTime = nil
        end
        MSUF_Gameplay_TickCombatTimer()
    end

    -- Unregister previous (idempotent)
    if type(MSUF_EventBus_Unregister) == "function" then
        MSUF_EventBus_Unregister("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_TIMER")
        MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_TIMER")
        MSUF_EventBus_Unregister("PLAYER_ENTERING_WORLD", "MSUF_COMBAT_TIMER")
    end
    _StopCombatTimerTick()

    if g.enableCombatTimer then
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_TIMER", _CombatTimer_OnRegenDisabled)
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_TIMER", _CombatTimer_OnRegenEnabled)
            MSUF_EventBus_Register("PLAYER_ENTERING_WORLD", "MSUF_COMBAT_TIMER", _CombatTimer_OnPEW)
        end

        -- If the user enables the timer while already in combat, show it immediately.
        if UnitAffectingCombat and UnitAffectingCombat("player") then
            if not combatStartTime then
                combatStartTime = GetTime()
            end
            wasInCombat = true
            lastTimerText = ""
            MSUF_Gameplay_TickCombatTimer()
            _StartCombatTimerTick()
        end
    else
        wasInCombat = false
        combatStartTime = nil
        lastTimerText = ""
    end
end

-- Backwards-compatible entrypoint used by other modules (e.g. Colors)
-- Apply all Gameplay visuals immediately (frames + fonts + colors).
function ns.MSUF_ApplyGameplayVisuals()
    -- This file also uses MSUF_RequestGameplayApply as the canonical apply path.
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

------------------------------------------------------
-- Options panel
------------------------------------------------------
function ns.MSUF_RegisterGameplayOptions_Full(parentCategory)
    local panel = (_G and _G.MSUF_GameplayPanel) or CreateFrame("Frame", "MSUF_GameplayPanel", UIParent)
    panel.name = "Gameplay"

    if panel.__MSUF_GameplayBuilt then
        return panel
    end

    local scrollFrame = CreateFrame("ScrollFrame", "MSUF_GameplayScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 0)

    local content = CreateFrame("Frame", "MSUF_GameplayScrollChild", scrollFrame)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    content:SetWidth(640)
    content:SetHeight(600)

    scrollFrame:SetScrollChild(content)

    local lastControl

    local function RequestApply()
        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
    end

    local function BindCheck(cb, key, after)
        cb:SetScript("OnClick", function(self)
            local g = EnsureGameplayDefaults()
            local oldVal = g[key]
            local newVal = self:GetChecked() and true or false
            g[key] = newVal

            -- One-time hint: ONLY when the user actually changes a setting here (not on menu open).
            -- Show it when enabling features whose colors live in Colors > Gameplay.
            if (oldVal ~= newVal) and newVal and (key == "enableCombatStateText" or key == "enableCombatCrosshair" or key == "enableCombatCrosshairMeleeRangeColor") then
                if ns and ns.MSUF_MaybeShowGameplayColorsTip then
                    ns.MSUF_MaybeShowGameplayColorsTip()
                end
            end

            if after then after(self, g) end

            -- Keep UI state consistent with Main menu behavior:
            -- when a parent toggle is off, dependent controls are disabled/greyed out.
            if panel and panel.MSUF_UpdateGameplayDisabledStates then
                panel:MSUF_UpdateGameplayDisabledStates()
            end

            RequestApply()
        end)
    end

	    local function BindSlider(sl, key, roundFunc, after, applyNow)
        sl:SetScript("OnValueChanged", function(self, value)
            -- UI sync (panel:refresh / drag-sync) should not write DB or trigger apply.
            if panel and panel._msufSuppressSliderChanges then
                return
            end
	            local g = EnsureGameplayDefaults()
	            -- Defensive: only call a real round/transform function.
	            if type(roundFunc) == "function" then
	                value = roundFunc(value)
	            end
            g[key] = value
            if after then after(self, g, value) end
            if applyNow then RequestApply() end
        end)
    end

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Midnight Simple Unit Frames - Gameplay")

    local subText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subText:SetWidth(600)
    subText:SetJustifyH("LEFT")
    subText:SetText("Here are several gameplay enhancement options you can toggle on or off.")

    -- Section header + separator line
    local sectionTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sectionTitle:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", 0, -14)
    sectionTitle:SetText("Crosshair melee spell")

    local separator = content:CreateTexture(nil, "ARTWORK")
    separator:SetColorTexture(1, 1, 1, 0.15)
    separator:SetPoint("TOPLEFT", sectionTitle, "BOTTOMLEFT", 0, -4)
    separator:SetSize(560, 1)

    sectionTitle:Hide()
    separator:Hide()

-- Shared melee range spell (shared)
local meleeSharedTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
meleeSharedTitle:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 0, -18)
meleeSharedTitle:SetText("Melee range spell (crosshair)")
panel.meleeSharedTitle = meleeSharedTitle

local meleeSharedSubText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
meleeSharedSubText:SetPoint("TOPLEFT", meleeSharedTitle, "BOTTOMLEFT", 0, -4)
meleeSharedSubText:SetText("Used by: Crosshair melee-range color.")
panel.meleeSharedSubText = meleeSharedSubText

local meleeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
meleeLabel:SetPoint("TOPLEFT", meleeSharedSubText, "BOTTOMLEFT", 0, -10)
meleeLabel:SetText("Choose spell (type spell ID or name):")
panel.meleeSpellChooseLabel = meleeLabel

local meleeInput = CreateFrame("EditBox", "MSUF_Gameplay_MeleeSpellInput", content, "InputBoxTemplate")
meleeInput:SetSize(240, 20)
meleeInput:SetPoint("TOPLEFT", meleeLabel, "BOTTOMLEFT", -4, -6)
meleeInput:SetAutoFocus(false)
meleeInput:SetMaxLetters(60)
panel.meleeSpellInput = meleeInput
local MSUF_SuppressMeleeInputChange = false
local MSUF_SkipMeleeFocusLostResolve = false

-- Optional per-class storage for the shared melee range spell.
-- This allows users to keep one profile across multiple characters and still
-- use a valid class spell for range checking.
local perClassCB = CreateFrame("CheckButton", "MSUF_Gameplay_MeleeSpellPerClassCheck", content, "InterfaceOptionsCheckButtonTemplate")
perClassCB:SetPoint("TOPLEFT", meleeInput, "BOTTOMLEFT", 4, -6)
perClassCB.Text:SetText("Store per class")
panel.meleeSpellPerClassCheck = perClassCB

local perClassHint = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
perClassHint:SetPoint("TOPLEFT", perClassCB, "BOTTOMLEFT", 20, -2)
perClassHint:SetText("Keeps per character settings.")
panel.meleeSpellPerClassHint = perClassHint

local meleeSelected = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
meleeSelected:SetPoint("LEFT", meleeInput, "RIGHT", 12, 0)
meleeSelected:SetText("Selected: (none)")
panel.meleeSpellSelectedText = meleeSelected

local meleeUsedBy = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
meleeUsedBy:SetPoint("TOPLEFT", meleeSelected, "BOTTOMLEFT", 0, -6)
meleeUsedBy:SetText("Used by: Crosshair color")
panel.meleeSpellUsedByText = meleeUsedBy

local meleeSharedWarn = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
meleeSharedWarn:SetPoint("TOPLEFT", meleeUsedBy, "BOTTOMLEFT", 0, -2)
meleeSharedWarn:SetText("|cffff8800No melee range spell selected â€” Crosshair will not work.|r")
meleeSharedWarn:Hide()
panel.meleeSpellWarningText = meleeSharedWarn

local suggestionFrame = CreateFrame("Frame", "MSUF_Gameplay_MeleeSpellSuggestions", content, "BackdropTemplate")
suggestionFrame:SetPoint("TOPLEFT", meleeInput, "BOTTOMLEFT", 0, -2)
suggestionFrame:SetSize(360, 8 * 18 + 10)
suggestionFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
suggestionFrame:SetBackdropColor(0, 0, 0, 0.85)
-- Ensure the dropdown is clickable and sits above other controls (sliders, checkboxes)
suggestionFrame:SetFrameStrata("TOOLTIP")
suggestionFrame:SetToplevel(true)
suggestionFrame:SetClampedToScreen(true)
suggestionFrame:SetFrameLevel((content and content.GetFrameLevel and (content:GetFrameLevel() + 200)) or 200)
suggestionFrame:Hide()
panel.meleeSuggestionFrame = suggestionFrame

-- Forward declare so suggestion button OnClick closures can call it safely.
local MSUF_SelectMeleeSpell

local suggestionButtons = {}
for i = 1, 8 do
    local b = CreateFrame("Button", nil, suggestionFrame)
    b:SetSize(340, 18)
    b:SetPoint("TOPLEFT", suggestionFrame, "TOPLEFT", 10, -6 - (i - 1) * 18)
    b:SetFrameLevel(suggestionFrame:GetFrameLevel() + i)

    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", b, "LEFT", 0, 0)
    t:SetJustifyH("LEFT")
    b.text = t

    b:SetScript("OnClick", function(selfBtn)
        local data = selfBtn.data
        if not data then return end
        -- Route through the shared selection helper so per-class storage stays in sync.
        MSUF_SelectMeleeSpell(data.id, data.name, true)
        MSUF_SkipMeleeFocusLostResolve = true
        meleeInput:ClearFocus()
        suggestionFrame:Hide()
    end)

    suggestionButtons[i] = b
end

local function UpdateSelectedTextFromDB()
    local g = EnsureGameplayDefaults()
    local id = 0
    if g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
        local _, class = UnitClass("player")
        if class then
            id = tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0
        end
    end
    if id <= 0 then
        id = tonumber(g.nameplateMeleeSpellID) or 0
    end
    -- Shared spell warnings (only relevant if crosshair range-color mode is enabled)
    local rangeActive = (g.enableCombatCrosshair and g.enableCombatCrosshairMeleeRangeColor) and true or false
    if panel and panel.meleeSpellWarningText then
        if rangeActive and id <= 0 then
            panel.meleeSpellWarningText:Show()
        else
            panel.meleeSpellWarningText:Hide()
        end
    end
    if panel and panel.crosshairRangeWarnText then
        if rangeActive and id <= 0 then
            panel.crosshairRangeWarnText:Show()
        else
            panel.crosshairRangeWarnText:Hide()
        end
    end

    if id > 0 then
        local name
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(id)
            if info then name = info.name end
        end
        if not name and GetSpellInfo then
            name = GetSpellInfo(id)
        end
        if name then
            meleeSelected:SetText(string_format("Selected: %s (%d)", name, id))
        else
            meleeSelected:SetText(string_format("Selected: ID %d", id))
        end
    else
        meleeSelected:SetText("Selected: (none)")
    end
end

local function QuerySuggestions(query)
    MSUF_BuildMeleeSpellCache()
    if not MSUF_MeleeSpellCache or #MSUF_MeleeSpellCache == 0 then
        return {}
    end

    local q = string_lower(query or "")
    if q == "" then
        return {}
    end

    local out = {}
    for _, s in ipairs(MSUF_MeleeSpellCache) do
        if s.lower and s.lower:find(q, 1, true) then
            out[#out + 1] = s
            if #out >= 8 then
                break
            end
        end
    end
    return out
end

MSUF_SelectMeleeSpell = function(spellID, spellName, preferNameInBox)
    local g = EnsureGameplayDefaults()
    spellID = tonumber(spellID) or 0
    if spellID <= 0 then return end

    -- Persist selection (global + optional per-class)
    if g.meleeSpellPerClass then
        if type(g.nameplateMeleeSpellIDByClass) ~= "table" then
            g.nameplateMeleeSpellIDByClass = {}
        end
        if UnitClass then
            local _, class = UnitClass("player")
            if class then
                g.nameplateMeleeSpellIDByClass[class] = spellID
            end
        end
    end
    g.nameplateMeleeSpellID = spellID

    if preferNameInBox and spellName and spellName ~= "" then
        MSUF_SuppressMeleeInputChange = true
        meleeInput:SetText(spellName)
        MSUF_SuppressMeleeInputChange = false
    end

    meleeSelected:SetText(string_format("Selected: %s (%d)", (spellName and spellName ~= "" and spellName) or ("ID " .. spellID), spellID))
    if g.enableCombatCrosshair and g.enableCombatCrosshairMeleeRangeColor then
        MSUF_SetEnabledMeleeRangeCheck(spellID)
    end
    ns.MSUF_RequestGameplayApply()
end

local function MSUF_ResolveTypedMeleeSpell(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end

    local asNum = tonumber(text)
    if asNum and asNum > 0 then
        local name
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(asNum)
            if info then name = info.name end
        end
        if (not name) and GetSpellInfo then
            name = GetSpellInfo(asNum)
        end
        return asNum, name
    end

    local q = string_lower(text)
    local results = QuerySuggestions(text)
    -- Prefer exact match (case-insensitive)
    for i = 1, #results do
        if results[i] and results[i].lower == q then
            return results[i].id, results[i].name
        end
    end
    -- Otherwise, pick first suggestion
    if results[1] then
        return results[1].id, results[1].name
    end
    return nil
end

meleeInput:SetScript("OnEnterPressed", function(self)
    -- If dropdown is open, choose the first visible suggestion; otherwise try resolving typed text.
    local first = suggestionButtons[1] and suggestionButtons[1].data
    if suggestionFrame:IsShown() and first and first.id then
        MSUF_SelectMeleeSpell(first.id, first.name, true)
        suggestionFrame:Hide()
        MSUF_SkipMeleeFocusLostResolve = true
        self:ClearFocus()
        return
    end

    local id, name = MSUF_ResolveTypedMeleeSpell(self:GetText())
    if id then
        MSUF_SelectMeleeSpell(id, name, true)
    end
    suggestionFrame:Hide()
    MSUF_SkipMeleeFocusLostResolve = true
    self:ClearFocus()
end)
meleeInput:SetScript("OnTextChanged", function(self)
    if MSUF_SuppressMeleeInputChange then return end
    local txt = self:GetText() or ""
    local g = EnsureGameplayDefaults()

    local asNum = tonumber(txt)
    if asNum and asNum > 0 then
        if g.meleeSpellPerClass then
            if type(g.nameplateMeleeSpellIDByClass) ~= "table" then
                g.nameplateMeleeSpellIDByClass = {}
            end
            if UnitClass then
                local _, class = UnitClass("player")
                if class then
                    g.nameplateMeleeSpellIDByClass[class] = asNum
                end
            end
        end
        g.nameplateMeleeSpellID = asNum
        UpdateSelectedTextFromDB()
        if g.enableCombatCrosshair and g.enableCombatCrosshairMeleeRangeColor then
            MSUF_SetEnabledMeleeRangeCheck(asNum)
            ns.MSUF_RequestGameplayApply()
        end
        suggestionFrame:Hide()
        return
    end

    local results = QuerySuggestions(txt)
    if #results == 0 then
        suggestionFrame:Hide()
        return
    end

    for i = 1, 8 do
        local b = suggestionButtons[i]
        local data = results[i]
        if data then
            b.data = data
            b.text:SetText(string_format("%s (%d)", data.name, data.id))
            b:Show()
        else
            b.data = nil
            b.text:SetText("")
            b:Hide()
        end
    end
    suggestionFrame:Show()
end)

-- Per-class checkbox behavior.
perClassCB:SetScript("OnClick", function(self)
    local g = EnsureGameplayDefaults()
    local want = self:GetChecked() and true or false
    g.meleeSpellPerClass = want
    if want then
        if type(g.nameplateMeleeSpellIDByClass) ~= "table" then
            g.nameplateMeleeSpellIDByClass = {}
        end
        if UnitClass then
            local _, class = UnitClass("player")
            if class then
                -- Seed class entry from current global spell if missing.
                if not g.nameplateMeleeSpellIDByClass[class] or tonumber(g.nameplateMeleeSpellIDByClass[class]) <= 0 then
                    g.nameplateMeleeSpellIDByClass[class] = tonumber(g.nameplateMeleeSpellID) or 0
                end
            end
        end
    end

    -- Refresh UI + apply immediately.
    if panel and panel.refresh then
        panel:refresh()
    end
    ns.MSUF_RequestGameplayApply()
end)

meleeInput:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    suggestionFrame:Hide()
    UpdateSelectedTextFromDB()
end)

meleeInput:SetScript("OnEditFocusLost", function(self)
    suggestionFrame:Hide()
    if MSUF_SkipMeleeFocusLostResolve then
        MSUF_SkipMeleeFocusLostResolve = false
        UpdateSelectedTextFromDB()
        return
    end
    local id, name = MSUF_ResolveTypedMeleeSpell(self:GetText())
    if id then
        MSUF_SelectMeleeSpell(id, name, true)
    else
        UpdateSelectedTextFromDB()
    end
end)

    ------------------------------------------------------
    -- Options UI builder helpers (single-file factory)
    -- NOTE: Keep layout pixel-identical by preserving all SetPoint offsets.
    ------------------------------------------------------
    local function _MSUF_Sep(topRef, yOff)
        local t = content:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, 0.15)
        t:SetPoint("TOP", topRef, "BOTTOM", 0, yOff or -24)
        t:SetPoint("LEFT", content, "LEFT", 20, 0)
        t:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        t:SetHeight(1)
        return t
    end

    local function _MSUF_Header(sep, text)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        fs:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -10)
        fs:SetText(text)
        return fs
    end

    local function _MSUF_Label(template, point, rel, relPoint, x, y, text, field)
        local fs = content:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
        fs:SetPoint(point, rel, relPoint, x or 0, y or 0)
        fs:SetText(text or "")
        if field then panel[field] = fs end
        return fs
    end

    local function _MSUF_Check(name, point, rel, relPoint, x, y, text, field, key, after)
        local cb = CreateFrame("CheckButton", name, content, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint(point, rel, relPoint, x or 0, y or 0)
        cb.Text:SetText(text or "")
        if field then panel[field] = cb end
        if key then BindCheck(cb, key, after) end
        return cb
    end

    local function _MSUF_ColorSwatch(name, point, rel, relPoint, x, y, labelText, field, key, defaultRGB, after)
        local btn = CreateFrame("Button", name, content, "BackdropTemplate")
        btn:SetPoint(point, rel, relPoint, x or 0, y or 0)
        btn:SetSize(18, 18)
        btn:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        btn:SetBackdropColor(0, 0, 0, 0.8)
        btn:SetBackdropBorderColor(1, 1, 1, 0.25)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local sw = btn:CreateTexture(nil, "ARTWORK")
        sw:SetAllPoints()
        btn._msufSwatch = sw

        local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("LEFT", btn, "RIGHT", 8, 0)
        label:SetText(labelText or "")
        btn._msufLabel = label

        if field then panel[field] = btn end

        local function GetDefault()
            if type(defaultRGB) == "table" then
                return defaultRGB[1] or 1, defaultRGB[2] or 1, defaultRGB[3] or 1
            end
            return 1, 1, 1
        end

        function btn:MSUF_Refresh()
            local g = EnsureGameplayDefaults()
            local dr, dg, db = GetDefault()
            local r, g2, b = _MSUF_NormalizeRGB(g and g[key], dr, dg, db)
            self._msufSwatch:SetColorTexture(r, g2, b, 1)
        end

        local function ApplyColor(r, g2, b)
            local g = EnsureGameplayDefaults()
            g[key] = { r, g2, b }
            btn:MSUF_Refresh()
            if type(after) == "function" then
                after()
            end
            ns.MSUF_RequestGameplayApply()
        end

        btn:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                local r, g2, b = GetDefault()
                ApplyColor(r, g2, b)
                return
            end

            if not ColorPickerFrame then
                return
            end

            local g = EnsureGameplayDefaults()
            local r, g2, b = _MSUF_NormalizeRGB(g and g[key], 1, 1, 1)

            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.previousValues = { r, g2, b }

            ColorPickerFrame.func = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                ApplyColor(nr, ng, nb)
            end

            ColorPickerFrame.cancelFunc = function(prev)
                if type(prev) == "table" then
                    ApplyColor(prev[1] or 1, prev[2] or 1, prev[3] or 1)
                end
            end

            ColorPickerFrame:SetColorRGB(r, g2, b)
            ColorPickerFrame:Show()
        end)

        btn:MSUF_Refresh()
        return btn, label
    end

    local function _MSUF_Slider(name, point, rel, relPoint, x, y, width, lo, hi, step, lowText, highText, titleText, field, key, roundFunc, after, applyNow)
        local sl = CreateFrame("Slider", name, content, "OptionsSliderTemplate")
        sl:SetWidth(width or 220)
        sl:SetPoint(point, rel, relPoint, x or 0, y or 0)
        sl:SetMinMaxValues(lo, hi)
        sl:SetValueStep(step)
        sl:SetObeyStepOnDrag(true)

        local base = sl:GetName()
        if lowText then _G[base .. "Low"]:SetText(lowText) end
        if highText then _G[base .. "High"]:SetText(highText) end
        if titleText then _G[base .. "Text"]:SetText(titleText) end

        if field then panel[field] = sl end
        if key then BindSlider(sl, key, roundFunc, after, applyNow) end
        return sl
    end

    local function _MSUF_SliderTextRight(name)
        local t = _G[name .. "Text"]
        if t then
            t:ClearAllPoints()
            t:SetPoint("LEFT", _G[name], "RIGHT", 12, 0)
            t:SetJustifyH("LEFT")
        end
    end

    local function _MSUF_EditBox(name, point, rel, relPoint, x, y, w, h, field)
        local eb = CreateFrame("EditBox", name, content, "InputBoxTemplate")
        eb:SetSize(w or 220, h or 20)
        eb:SetAutoFocus(false)
        eb:SetPoint(point, rel, relPoint, x or 0, y or 0)
        if field then panel[field] = eb end
        return eb
    end
    local function _MSUF_Button(name, point, rel, relPoint, x, y, w, h, text, field, onClick)
        local b = CreateFrame("Button", name, content, "UIPanelButtonTemplate")
        b:SetSize(w or 60, h or 20)
        b:SetPoint(point, rel, relPoint, x or 0, y or 0)
        b:SetText(text or "")
        if field then panel[field] = b end
        if type(onClick) == "function" then
            b:SetScript("OnClick", onClick)
        end
        return b
    end

local function _MSUF_Dropdown(name, point, rel, relPoint, x, y, width, field)
    -- Simple UIDropDownMenu-based control (used sparingly in Gameplay to avoid heavy UI scaffolding).
    local dd = CreateFrame("Frame", name, content, "UIDropDownMenuTemplate")
    dd:SetPoint(point, rel, relPoint, x or 0, y or 0)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dd, width or 120)
    end
    if field then
        panel[field] = dd
    end
    return dd
end

    -- Combat Timer header + separator
    local combatSeparator = _MSUF_Sep(subText, -36)
    local combatHeader = _MSUF_Header(combatSeparator, "Combat Timer")

    -- In-combat timer checkbox
    local combatTimerCheck = _MSUF_Check("MSUF_Gameplay_CombatTimerCheck", "TOPLEFT", combatHeader, "BOTTOMLEFT", 0, -8, "Enable in-combat timer", "combatTimerCheck", "enableCombatTimer")

    -- Combat Timer anchor dropdown (None / Player / Target / Focus)
    local combatTimerAnchorLabel = _MSUF_Label("GameFontNormal", "LEFT", combatTimerCheck, "RIGHT", 220, 0, "Anchor", "combatTimerAnchorLabel")
    local combatTimerAnchorDD = _MSUF_Dropdown("MSUF_Gameplay_CombatTimerAnchorDropDown", "LEFT", combatTimerAnchorLabel, "RIGHT", 6, -2, 120, "combatTimerAnchorDropdown")

    local function _CombatTimerAnchor_Validate(v)
        if v ~= "none" and v ~= "player" and v ~= "target" and v ~= "focus" then
            return "none"
        end
        return v
    end

    local function _CombatTimerAnchor_Text(v)
        if v == "player" then return "Player" end
        if v == "target" then return "Target" end
        if v == "focus" then return "Focus" end
        return "None"
    end

    local function _CombatTimerAnchor_Set(v)
        local g = MSUF_DB and MSUF_DB.gameplay
        if not g then return end

        local preX, preY
        if combatFrame and combatFrame.GetCenter then
            preX, preY = combatFrame:GetCenter()
        end

        local val = _CombatTimerAnchor_Validate(v)
        g.combatTimerAnchor = val

        -- Keep the timer in the same on-screen position when switching anchors
        if preX and preY then
            local anchor = _MSUF_GetCombatTimerAnchorFrame(g)
            local ax, ay
            if anchor and anchor.GetCenter then
                ax, ay = anchor:GetCenter()
            end
            if not ax or not ay then
                ax, ay = UIParent:GetCenter()
            end
            if ax and ay then
                g.combatOffsetX = preX - ax
                g.combatOffsetY = preY - ay
            end
        end

        
        -- Apply anchor immediately (independent of lock state)
        if combatFrame then
            MSUF_Gameplay_ApplyCombatTimerAnchor(g)
            -- Refresh preview text positioning right away (no 1s wait)
            MSUF_Gameplay_TickCombatTimer()
        end

        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(combatTimerAnchorDD, val) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(combatTimerAnchorDD, _CombatTimerAnchor_Text(val)) end

        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
        if panel and panel.refresh then
            panel:refresh()
        end
    end

    if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
        UIDropDownMenu_Initialize(combatTimerAnchorDD, function(self, level)
            local g = MSUF_DB and MSUF_DB.gameplay
            local cur = _CombatTimerAnchor_Validate(g and g.combatTimerAnchor)

            local items = {
                {"none",  "None"},
                {"player", "Player"},
                {"target", "Target"},
                {"focus",  "Focus"},
            }

            for i = 1, #items do
                local value = items[i][1]
                local text  = items[i][2]
                local info = UIDropDownMenu_CreateInfo()
                info.text = text
                info.value = value
                info.checked = (cur == value)
                info.func = function(btn)
                    _CombatTimerAnchor_Set(btn and btn.value)
                    if CloseDropDownMenus then CloseDropDownMenus() end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end

    do
        local g = MSUF_DB and MSUF_DB.gameplay
        local cur = _CombatTimerAnchor_Validate(g and g.combatTimerAnchor)
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(combatTimerAnchorDD, cur) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(combatTimerAnchorDD, _CombatTimerAnchor_Text(cur)) end
    end

    -- Combat Timer size slider
    local combatSlider = _MSUF_Slider("MSUF_Gameplay_CombatFontSizeSlider", "TOPLEFT", combatTimerCheck, "BOTTOMLEFT", 0, -24, 220, 10, 64, 1, "10 px", "64 px", "Timer size", "combatFontSizeSlider", "combatFontSize",
        function(v) return math.floor(v + 0.5) end,
        function() ApplyFontToCounter() end,
        false
    )

    -- Combat Timer lock checkbox
    local combatLock = _MSUF_Check("MSUF_Gameplay_LockCombatTimerCheck", "LEFT", combatSlider, "RIGHT", 40, 0, "Lock position", "lockCombatTimerCheck", "lockCombatTimer",
        function()
            ApplyLockState()
        end
    )

    -- Combat Enter/Leave header + separator
    local combatStateSeparator = _MSUF_Sep(combatSlider, -24)
    local combatStateHeader = _MSUF_Header(combatStateSeparator, "Combat Enter/Leave")

    -- Combat state text checkbox
    local combatStateCheck = _MSUF_Check("MSUF_Gameplay_CombatStateCheck", "TOPLEFT", combatStateHeader, "BOTTOMLEFT", 0, -8, "Show combat enter/leave text", "combatStateCheck", "enableCombatStateText")

    -- Custom texts (enter/leave)
    local combatStateEnterLabel = _MSUF_Label("GameFontNormal", "TOPLEFT", combatStateCheck, "BOTTOMLEFT", 0, -12, "Enter text", "combatStateEnterLabel")
    local combatStateEnterInput = _MSUF_EditBox("MSUF_Gameplay_CombatStateEnterInput", "TOPLEFT", combatStateEnterLabel, "BOTTOMLEFT", 0, -6, 220, 20, "combatStateEnterInput")

    local combatStateLeaveLabel = _MSUF_Label("GameFontNormal", "TOPLEFT", combatStateEnterInput, "BOTTOMLEFT", 0, -12, "Leave text", "combatStateLeaveLabel")
    local combatStateLeaveInput = _MSUF_EditBox("MSUF_Gameplay_CombatStateLeaveInput", "TOPLEFT", combatStateLeaveLabel, "BOTTOMLEFT", 0, -6, 220, 20, "combatStateLeaveInput")

    local function CommitCombatStateTexts()
        local g = EnsureGameplayDefaults()
        g.combatStateEnterText = (combatStateEnterInput:GetText() or "")
        g.combatStateLeaveText = (combatStateLeaveInput:GetText() or "")
        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
        -- If we're showing the unlocked preview, refresh it with the new text
        if g.enableCombatStateText and (not g.lockCombatState) and combatStateText then
            local enterText = g.combatStateEnterText
            if type(enterText) ~= "string" or enterText == "" then
                enterText = "+Combat"
            end
            combatStateText:SetText(enterText)
        end
    end

    combatStateEnterInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        CommitCombatStateTexts()
    end)
    combatStateEnterInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if panel and panel.refresh then
            panel:refresh()
        end
    end)
    combatStateEnterInput:SetScript("OnEditFocusLost", function()
        CommitCombatStateTexts()
    end)

    combatStateLeaveInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        CommitCombatStateTexts()
    end)
    combatStateLeaveInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if panel and panel.refresh then
            panel:refresh()
        end
    end)
    combatStateLeaveInput:SetScript("OnEditFocusLost", function()
        CommitCombatStateTexts()
    end)

    -- Combat Enter/Leave text size slider (shares range with combat timer)
    local combatStateSlider = _MSUF_Slider("MSUF_Gameplay_CombatStateFontSizeSlider", "TOPLEFT", combatStateLeaveInput, "BOTTOMLEFT", 0, -24, 220, 10, 64, 1, "10 px", "64 px", "Text size", "combatStateFontSizeSlider", "combatStateFontSize",
        function(v) return math.floor(v + 0.5) end,
        function() ApplyFontToCounter() end,
        false
    )

    -- Combat Enter/Leave lock checkbox (shares lock with combat timer)
    local combatStateLock = _MSUF_Check("MSUF_Gameplay_CombatStateLockCheck", "LEFT", combatStateLeaveInput, "RIGHT", 80, 0, "Lock position", "lockCombatStateCheck", "lockCombatState",
        function()
            ApplyLockState()
        end
    )

    -- Duration slider for combat enter/leave text
    local combatStateDurationSlider = _MSUF_Slider("MSUF_Gameplay_CombatStateDurationSlider", "LEFT", combatStateEnterInput, "RIGHT", 80, 0, 160, 0.5, 5.0, 0.5, "Short", "Long", "Duration (s)", "combatStateDurationSlider", "combatStateDuration",
        function(v) return math.floor(v * 10 + 0.5) / 10 end,
        nil,
        false
    )

    -- Reset button next to Duration (restore default 1.5s)
    local combatStateDurationReset = _MSUF_Button("MSUF_Gameplay_CombatStateDurationReset", "LEFT", combatStateSlider, "RIGHT", 40, 0, 60, 20, "Reset", "combatStateDurationResetButton")
    combatStateDurationReset:SetScript("OnClick", function()
        local g = EnsureGameplayDefaults()
        g.combatStateDuration = 1.5
        if panel and panel.combatStateDurationSlider then
            panel.combatStateDurationSlider:SetValue(1.5)
        end
        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
    end)

    -- Class-specific toggles header + separator
    local classSpecSeparator = _MSUF_Sep(combatStateSlider, -24)
    local classSpecHeader = _MSUF_Header(classSpecSeparator, "Class-specific toggles")

    -- Shaman: Player Totem tracker (player-only)
    local _isShaman = false
    local _isRogue = false
    if UnitClass then
        local _, _cls = UnitClass("player")
        _isShaman = (_cls == "SHAMAN")
        _isRogue = (_cls == "ROGUE")
    end

    local _classSpecAnchorRef = classSpecHeader
    local _totemsLeftBottom = nil
    local _totemsRightBottom = nil

    if _isShaman then
        local totemsTitle = _MSUF_Label("GameFontNormal", "TOPLEFT", classSpecHeader, "BOTTOMLEFT", 0, -10, "Shaman: Totem tracker", "playerTotemsTitle")
        panel.playerTotemsTitle = totemsTitle

        local totemsSub = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", totemsTitle, "BOTTOMLEFT", 0, -2, "Player-only. Secret-safe in combat.", "playerTotemsSubText")

        local totemsDismissHint = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", totemsSub, "BOTTOMLEFT", 0, -2, "Note: Right-click to dismiss totems is protected by Blizzard (secure) and not supported yet.", "playerTotemsDismissHint")
        panel.playerTotemsDismissHint = totemsDismissHint

        panel.playerTotemsSubText = totemsSub

        local totemsCheck = _MSUF_Check("MSUF_Gameplay_PlayerTotemsCheck", "TOPLEFT", totemsDismissHint, "BOTTOMLEFT", 0, -8, "Enable Totem tracker", "playerTotemsCheck", "enablePlayerTotems",
            function()
                if ns and ns.MSUF_RequestGameplayApply then
                    ns.MSUF_RequestGameplayApply()
                end
                if panel and panel.MSUF_UpdateGameplayDisabledStates then
                    panel:MSUF_UpdateGameplayDisabledStates()
                end
            end
        )

        local function _RefreshTotemsPreviewButton()
            if panel and panel.playerTotemsPreviewButton and panel.playerTotemsPreviewButton.SetText then
                local active = (ns and ns.MSUF_PlayerTotems_IsPreviewActive and ns.MSUF_PlayerTotems_IsPreviewActive()) and true or false
                panel.playerTotemsPreviewButton:SetText(active and "Stop preview" or "Preview")
            end
        end

        local totemsShowText = _MSUF_Check("MSUF_Gameplay_PlayerTotemsShowTextCheck", "TOPLEFT", totemsCheck, "BOTTOMLEFT", 0, -8, "Show cooldown text", "playerTotemsShowTextCheck", "playerTotemsShowText",
            function()
                if ns and ns.MSUF_RequestGameplayApply then
                    ns.MSUF_RequestGameplayApply()
                end
                if panel and panel.MSUF_UpdateGameplayDisabledStates then
                    panel:MSUF_UpdateGameplayDisabledStates()
                end
            end
        )

        local totemsScaleText = _MSUF_Check("MSUF_Gameplay_PlayerTotemsScaleTextCheck", "TOPLEFT", totemsShowText, "BOTTOMLEFT", 0, -8, "Scale text by icon size", "playerTotemsScaleByIconCheck", "playerTotemsScaleTextByIconSize",
            function()
                if ns and ns.MSUF_RequestGameplayApply then
                    ns.MSUF_RequestGameplayApply()
                end
                if panel and panel.MSUF_UpdateGameplayDisabledStates then
                    panel:MSUF_UpdateGameplayDisabledStates()
                end
            end
        )

        -- Preview button: keep it in the left column under the toggles (cleaner layout).
        -- Preview is Shaman-only and works even when the feature toggle is off (positioning).
        local totemsPreviewBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsPreviewButton", "TOPLEFT", totemsScaleText, "BOTTOMLEFT", 0, -12, 140, 22, "Preview", "playerTotemsPreviewButton")
        totemsPreviewBtn:SetScript("OnClick", function()
            if ns and ns.MSUF_PlayerTotems_TogglePreview then
                ns.MSUF_PlayerTotems_TogglePreview()
            end
            _RefreshTotemsPreviewButton()
        end)
        _RefreshTotemsPreviewButton()

        
-- Tip: positioning workflow
local totemsDragHint = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", totemsPreviewBtn, "BOTTOMLEFT", 0, -4, "Tip: Move the preview via mousedrag", "playerTotemsDragHint")
panel.playerTotemsDragHint = totemsDragHint

_totemsLeftBottom = totemsDragHint

	        -- Right column for layout/size controls (keeps the left side clean, avoids clipping)
	        local _totemsRightX = 300

	        local totemsIconSize = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsIconSizeSlider", "TOPLEFT", totemsCheck, "TOPLEFT", _totemsRightX, -2, 240, 8, 64, 1, "Small", "Big", "Icon size", "playerTotemsIconSizeSlider", "playerTotemsIconSize",
            function(v) return math.floor((v or 0) + 0.5) end,
            function()
                if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
            end,
            true
        )

        local totemsSpacing = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsSpacingSlider", "TOPLEFT", totemsIconSize, "BOTTOMLEFT", 0, -18, 240, 0, 20, 1, "Tight", "Wide", "Spacing", "playerTotemsSpacingSlider", "playerTotemsSpacing",
            function(v) return math.floor((v or 0) + 0.5) end,
            function() if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end end,
            true
        )

        local totemsOffsetX = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsOffsetXSlider", "TOPLEFT", totemsSpacing, "BOTTOMLEFT", 0, -18, 240, -200, 200, 1, "Left", "Right", "X offset", "playerTotemsOffsetXSlider", "playerTotemsOffsetX",
            function(v) return math.floor((v or 0) + 0.5) end,
            function() if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end end,
            true
        )

        local totemsOffsetY = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsOffsetYSlider", "TOPLEFT", totemsOffsetX, "BOTTOMLEFT", 0, -18, 240, -200, 200, 1, "Down", "Up", "Y offset", "playerTotemsOffsetYSlider", "playerTotemsOffsetY",
            function(v) return math.floor((v or 0) + 0.5) end,
            function() if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end end,
            true
        )

        local totemsFontSize = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsFontSizeSlider", "TOPLEFT", totemsOffsetY, "BOTTOMLEFT", 0, -18, 240, 8, 64, 1, "Small", "Big", "Font size", "playerTotemsFontSizeSlider", "playerTotemsFontSize",
            function(v) return math.floor((v or 0) + 0.5) end,
            function() if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end end,
            true
        )

        local totemsLayoutLabel = _MSUF_Label("GameFontNormal", "TOPLEFT", totemsFontSize, "BOTTOMLEFT", 0, -12, "Layout", "playerTotemsLayoutLabel")
        panel.playerTotemsLayoutLabel = totemsLayoutLabel

        local anchorPoints = {"TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT"}
        local function _NextAnchor(cur)
            if type(cur) ~= "string" then
                return anchorPoints[1]
            end
            for i=1,#anchorPoints do
                if anchorPoints[i] == cur then
                    local j = i + 1
                    if j > #anchorPoints then j = 1 end
                    return anchorPoints[j]
                end
            end
            return anchorPoints[1]
                end

        -- Growth direction dropdown (RIGHT / LEFT / UP / DOWN)
        local growthDD = _MSUF_Dropdown("MSUF_Gameplay_PlayerTotemsGrowthDropDown", "TOPLEFT", totemsLayoutLabel, "BOTTOMLEFT", -16, -10, 110, "playerTotemsGrowthDropdown")

        local function _TotemsGrowth_Validate(v)
            if v ~= "LEFT" and v ~= "RIGHT" and v ~= "UP" and v ~= "DOWN" then
                return "RIGHT"
            end
            return v
        end

        local function _TotemsGrowth_Set(v)
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then return end
            local val = _TotemsGrowth_Validate(v)
            g.playerTotemsGrowthDirection = val

            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(growthDD, val) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(growthDD, val) end

            if panel and panel.refresh then panel:refresh() end
            if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
        end

        if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
            UIDropDownMenu_Initialize(growthDD, function(self, level)
                local g = MSUF_DB and MSUF_DB.gameplay
                local cur = _TotemsGrowth_Validate(g and g.playerTotemsGrowthDirection)

                local items = {
                    {"RIGHT", "Grow Right"},
                    {"LEFT",  "Grow Left"},
                    {"UP",    "Vertical Up"},
                    {"DOWN",  "Vertical Down"},
                }

                for i = 1, #items do
                    local value = items[i][1]
                    local text  = items[i][2]
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = text
                    info.value = value
                    info.checked = (cur == value)
                    info.func = function(btn)
                        _TotemsGrowth_Set(btn and btn.value)
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
        end

        -- Initial label/selection (kept in sync by panel.refresh)
        do
            local g = MSUF_DB and MSUF_DB.gameplay
            local cur = _TotemsGrowth_Validate(g and g.playerTotemsGrowthDirection)
            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(growthDD, cur) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(growthDD, cur) end
        end

	        local anchorFromBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsAnchorFromBtn", "TOPLEFT", growthDD, "TOPRIGHT", 8, -4, 122, 20, "From: TOPLEFT", "playerTotemsAnchorFromButton", function()
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then return end
            g.playerTotemsAnchorFrom = _NextAnchor(g.playerTotemsAnchorFrom)
            if panel and panel.refresh then panel:refresh() end
            if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
        end)
        panel.playerTotemsAnchorFromButton = anchorFromBtn

	        local anchorToBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsAnchorToBtn", "TOPLEFT", growthDD, "BOTTOMLEFT", 16, -6, 240, 20, "To: BOTTOMLEFT", "playerTotemsAnchorToButton", function()
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then return end
            g.playerTotemsAnchorTo = _NextAnchor(g.playerTotemsAnchorTo)
            if panel and panel.refresh then panel:refresh() end
            if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
        end)
        panel.playerTotemsAnchorToButton = anchorToBtn

	        local resetTotemsBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsResetBtn", "TOPLEFT", anchorToBtn, "BOTTOMLEFT", 0, -6, 240, 20, "Reset Totem tracker layout", "playerTotemsResetButton", function()
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then return end
            g.playerTotemsShowText = true
            g.playerTotemsScaleTextByIconSize = true
            g.playerTotemsIconSize = 24
            g.playerTotemsSpacing = 4
            g.playerTotemsOffsetX = 0
            g.playerTotemsOffsetY = -6
            g.playerTotemsAnchorFrom = "TOPLEFT"
            g.playerTotemsAnchorTo = "BOTTOMLEFT"
            g.playerTotemsGrowthDirection = "RIGHT"
            g.playerTotemsFontSize = 14
            g.playerTotemsTextColor = { 1, 1, 1 }
            if panel and panel.refresh then panel:refresh() end
            if panel and panel.MSUF_UpdateGameplayDisabledStates then panel:MSUF_UpdateGameplayDisabledStates() end
            if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
        end)
        panel.playerTotemsResetButton = resetTotemsBtn
        _totemsRightBottom = resetTotemsBtn

        _classSpecAnchorRef = resetTotemsBtn
    else
        local shamanHint = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", classSpecHeader, "BOTTOMLEFT", 0, -10, "(Totem tracker is Shaman-only)", "playerTotemsNotShamanHint")
        panel.playerTotemsNotShamanHint = shamanHint
        _classSpecAnchorRef = shamanHint
    end

    -- Rogue: "The First Dance" tracker (separate class block)
    -- Place it clearly BELOW the Shaman block (right column bottom), aligned to the left column.
    local _rogueAnchorRef = _classSpecAnchorRef
    local _rogueSep = nil

    do
        -- If we're Shaman, _classSpecAnchorRef points at the right-column reset button.
        -- Add a subtle divider that spans both columns, then anchor Rogue block under it.
        local _sepX = (_isShaman and -300) or 0
        _rogueSep = panel:CreateTexture(nil, "ARTWORK")
        _rogueSep:SetColorTexture(1, 1, 1, 0.06)
        _rogueSep:SetHeight(1)
        _rogueSep:SetPoint("TOPLEFT", _rogueAnchorRef, "BOTTOMLEFT", _sepX, -18)
        _rogueSep:SetPoint("TOPRIGHT", _rogueAnchorRef, "BOTTOMRIGHT", 0, -18)
    end

    local rogueTitle = _MSUF_Label("GameFontNormal", "TOPLEFT", _rogueSep, "BOTTOMLEFT", 0, -12, "Rogue: First Dance tracker", "firstDanceTitle")
    local rogueSub = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", rogueTitle, "BOTTOMLEFT", 0, -2, "Optional helper. Shows a 6s timer after leaving combat.", "firstDanceSubText")
    local firstDanceCheck = _MSUF_Check("MSUF_Gameplay_FirstDanceCheck", "TOPLEFT", rogueSub, "BOTTOMLEFT", 0, -10, "Track 'The First Dance' (6s after leaving combat)", "firstDanceCheck", "enableFirstDanceTimer")
    if not _isRogue then
        firstDanceCheck:SetEnabled(false)
    end

    -- Combat crosshair header + separator

    local _classSpecBottom = firstDanceCheck
    local crosshairSeparator = _MSUF_Sep(_classSpecBottom, -20)
    local crosshairHeader = _MSUF_Header(crosshairSeparator, "Combat crosshair")

    -- Generic combat crosshair (all classes)
    local combatCrosshairCheck = _MSUF_Check("MSUF_Gameplay_CombatCrosshairCheck", "TOPLEFT", crosshairHeader, "BOTTOMLEFT", 0, -8, "Show green combat crosshair under player (in combat)", "combatCrosshairCheck", "enableCombatCrosshair",
        function() if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end end
    )

    -- Combat crosshair: melee range coloring (uses the shared melee spell selection)
    local crosshairRangeColorCheck = _MSUF_Check("MSUF_Gameplay_CrosshairRangeColorCheck", "TOPLEFT", combatCrosshairCheck, "BOTTOMLEFT", 0, -8, "Crosshair: color by melee range to target (green=in range, red=out)", "crosshairRangeColorCheck", "enableCombatCrosshairMeleeRangeColor",
        function() if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end end
    )

    local crosshairRangeHint = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", crosshairRangeColorCheck, "BOTTOMLEFT", 24, -2, "Uses the spell selected below.", "crosshairRangeHintText")

    local crosshairRangeWarn = _MSUF_Label("GameFontNormalSmall", "TOPLEFT", crosshairRangeHint, "BOTTOMLEFT", 0, -2, "|cffff8800No melee range spell selected â€” Crosshair will not work.|r", "crosshairRangeWarnText")
    crosshairRangeWarn:Hide()

    -- Move "Melee range spell" selector into the Combat crosshair section (no separate header)
    if meleeSharedTitle and meleeSharedSubText and meleeLabel and meleeInput and meleeSelected and meleeUsedBy then
        meleeSharedTitle:ClearAllPoints()
        meleeSharedTitle:SetPoint("TOPLEFT", crosshairRangeWarn, "BOTTOMLEFT", 0, -12)

        meleeSharedSubText:ClearAllPoints()
        meleeSharedSubText:SetPoint("TOPLEFT", meleeSharedTitle, "BOTTOMLEFT", 0, -4)

        meleeLabel:ClearAllPoints()
        meleeLabel:SetPoint("TOPLEFT", meleeSharedSubText, "BOTTOMLEFT", 0, -10)

        meleeInput:ClearAllPoints()
        meleeInput:SetPoint("TOPLEFT", meleeLabel, "BOTTOMLEFT", -4, -6)

        meleeSelected:ClearAllPoints()
        meleeSelected:SetPoint("LEFT", meleeInput, "RIGHT", 12, 0)

        meleeUsedBy:ClearAllPoints()
        meleeUsedBy:SetPoint("TOPLEFT", meleeSelected, "BOTTOMLEFT", 0, -6)

        if meleeSharedWarn then
            -- Place the orange warning ABOVE "Selected" so it doesn't overlap the thickness/size sliders below.
            -- (Selected is horizontally in the right column; keeping the warning there avoids crowding the left label.)
            meleeSharedWarn:ClearAllPoints()
            meleeSharedWarn:SetPoint("BOTTOMLEFT", meleeSelected, "TOPLEFT", 0, 4)
        end
    end

    -- Crosshair preview (in-menu)
    -- Shows a live preview of size/thickness and (optionally) the melee-range color mode.
    local crosshairPreview = CreateFrame("Frame", "MSUF_Gameplay_CrosshairPreview", content, "BackdropTemplate")
    crosshairPreview:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    crosshairPreview:SetBackdropColor(0, 0, 0, 0.35)
    crosshairPreview:SetBackdropBorderColor(1, 1, 1, 0.15)
    crosshairPreview:SetSize(260, 120)
    if meleeInput then
        crosshairPreview:SetPoint("TOPLEFT", meleeInput, "BOTTOMLEFT", -4, -20)
    else
        crosshairPreview:SetPoint("TOPLEFT", crosshairRangeWarn, "BOTTOMLEFT", 0, -20)
    end
    panel.crosshairPreviewFrame = crosshairPreview

    local previewTitle = crosshairPreview:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    previewTitle:SetPoint("TOPLEFT", crosshairPreview, "TOPLEFT", 8, -6)
    previewTitle:SetText("Preview")

    local previewBox = CreateFrame("Frame", nil, crosshairPreview)
    previewBox:SetPoint("TOPLEFT", crosshairPreview, "TOPLEFT", 8, -20)
    previewBox:SetPoint("BOTTOMRIGHT", crosshairPreview, "BOTTOMRIGHT", -8, 8)

    -- A small center anchor inside the preview box
    local previewCenter = CreateFrame("Frame", nil, previewBox)
    previewCenter:SetSize(1, 1)
    previewCenter:SetPoint("CENTER")

    local pLeft  = previewBox:CreateTexture(nil, "ARTWORK")
    local pRight = previewBox:CreateTexture(nil, "ARTWORK")
    local pUp    = previewBox:CreateTexture(nil, "ARTWORK")
    local pDown  = previewBox:CreateTexture(nil, "ARTWORK")
    pLeft:SetColorTexture(1, 1, 1, 1)
    pRight:SetColorTexture(1, 1, 1, 1)
    pUp:SetColorTexture(1, 1, 1, 1)
    pDown:SetColorTexture(1, 1, 1, 1)

    crosshairPreview._phase = 0
    crosshairPreview._elapsed = 0

    local function ClampInt(v, lo, hi)
        v = tonumber(v) or lo
        v = math.floor(v + 0.5)
        if v < lo then v = lo end
        if v > hi then v = hi end
        return v
    end

    local function UpdateCrosshairPreview()
        local g = EnsureGameplayDefaults()

        local thickness = ClampInt(g.crosshairThickness or 2, 1, 10)
        local size = ClampInt(g.crosshairSize or 40, 20, 80)

        -- Fit the preview box (leave padding for the title)
        local maxW = math_max(10, (previewBox:GetWidth() or 200) - 10)
        local maxH = math_max(10, (previewBox:GetHeight() or 80) - 10)
        local maxSize = math_min(size, maxW, maxH)
        if maxSize < 10 then maxSize = 10 end

        local gap = math_max(2, thickness * 2)
        if gap > maxSize - 2 then
            gap = maxSize - 2
        end

        local seg = (maxSize - gap) / 2
        if seg < 1 then seg = 1 end

        -- Layout
        pLeft:ClearAllPoints()
        pLeft:SetPoint("RIGHT", previewCenter, "CENTER", -gap / 2, 0)
        pLeft:SetSize(seg, thickness)

        pRight:ClearAllPoints()
        pRight:SetPoint("LEFT", previewCenter, "CENTER", gap / 2, 0)
        pRight:SetSize(seg, thickness)

        pUp:ClearAllPoints()
        pUp:SetPoint("BOTTOM", previewCenter, "CENTER", 0, gap / 2)
        pUp:SetSize(thickness, seg)

        pDown:ClearAllPoints()
        pDown:SetPoint("TOP", previewCenter, "CENTER", 0, -gap / 2)
        pDown:SetSize(thickness, seg)

        if not (g.enableCombatCrosshair and g.enableCombatCrosshairMeleeRangeColor) then
            crosshairPreview._phase = 0
        end

        -- Color
        local inT = g.crosshairInRangeColor
        local outT = g.crosshairOutRangeColor
        local inR, inG, inB = (inT and inT[1]) or 0, (inT and inT[2]) or 1, (inT and inT[3]) or 0
        local outR, outG, outB = (outT and outT[1]) or 1, (outT and outT[2]) or 0, (outT and outT[3]) or 0

        local r, gCol, b, a = inR, inG, inB, 1
        if not g.enableCombatCrosshair then
            r, gCol, b, a = 0.6, 0.6, 0.6, 0.35
        else
            if g.enableCombatCrosshairMeleeRangeColor then
                -- Alternate between in-range and out-of-range preview
                if crosshairPreview._phase == 1 then
                    r, gCol, b, a = outR, outG, outB, 1
                end
            end
        end
        pLeft:SetVertexColor(r, gCol, b, a)
        pRight:SetVertexColor(r, gCol, b, a)
        pUp:SetVertexColor(r, gCol, b, a)
        pDown:SetVertexColor(r, gCol, b, a)

        -- Only animate (green <-> red) when range-color mode is enabled
        if g.enableCombatCrosshair and g.enableCombatCrosshairMeleeRangeColor then
            crosshairPreview:SetScript("OnUpdate", function(self, elapsed)
                self._elapsed = (self._elapsed or 0) + (elapsed or 0)
                if self._elapsed >= 0.85 then
                    self._elapsed = 0
                    self._phase = (self._phase == 1) and 0 or 1
                    UpdateCrosshairPreview()
                end
            end)
        else
            crosshairPreview:SetScript("OnUpdate", nil)
            crosshairPreview._elapsed = 0
            crosshairPreview._phase = 0
        end
    end

    panel.MSUF_UpdateCrosshairPreview = UpdateCrosshairPreview

    -- Combat crosshair thickness slider
    local crosshairThicknessLabel = _MSUF_Label("GameFontHighlight", "TOPLEFT", meleeSelected or (meleeSharedWarn or crosshairRangeWarn), "BOTTOMLEFT", 0, -24, "Crosshair thickness", "crosshairThicknessLabel")

    local crosshairThicknessSlider = _MSUF_Slider("MSUF_Gameplay_CrosshairThicknessSlider", "TOPLEFT", crosshairThicknessLabel, "BOTTOMLEFT", 0, -12, 240, 1, 10, 1, "1 px", "10 px", "2 px", "crosshairThicknessSlider", "crosshairThickness",
        function(v) return math.floor(v + 0.5) end,
        function(self, g, v)
            _G[self:GetName() .. "Text"]:SetText(string.format("%d px", v))
            if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end
        end,
        true
    )
    _MSUF_SliderTextRight("MSUF_Gameplay_CrosshairThicknessSlider")

    if crosshairPreview and crosshairThicknessSlider then
        -- Keep the preview in the left column (no overlap with sliders)
        crosshairPreview:SetPoint("TOPRIGHT", crosshairThicknessSlider, "TOPLEFT", -18, 0)
    end

    -- Combat crosshair size slider
    local crosshairSizeLabel = _MSUF_Label("GameFontHighlight", "TOPLEFT", crosshairThicknessSlider, "BOTTOMLEFT", 0, -24, "Crosshair size", "crosshairSizeLabel")

    local crosshairSizeSlider = _MSUF_Slider("MSUF_Gameplay_CrosshairSizeSlider", "TOPLEFT", crosshairSizeLabel, "BOTTOMLEFT", 0, -14, 240, 20, 80, 2, "20 px", "80 px", "40 px", "crosshairSizeSlider", "crosshairSize",
        function(v)
            v = math.floor(v + 0.5)
            if v < 20 then v = 20 elseif v > 80 then v = 80 end
            return v
        end,
        function(self, g, v)
            _G[self:GetName() .. "Text"]:SetText(string.format("%d px", v))
            if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end
        end,
        true
    )
    _MSUF_SliderTextRight("MSUF_Gameplay_CrosshairSizeSlider")

    if crosshairPreview and crosshairSizeSlider then
        crosshairPreview:SetPoint("BOTTOMRIGHT", crosshairSizeSlider, "BOTTOMLEFT", -18, -4)
    end

    -- Cooldown manager header + separator
    local cooldownSeparator = _MSUF_Sep(crosshairSizeSlider, -30)
    local cooldownHeader = _MSUF_Header(cooldownSeparator, "Cooldown Manager")
    -- NOTE: Temporarily disabled until CooldownManager integration is reworked.
    local cooldownIconsCheck = _MSUF_Check("MSUF_Gameplay_CooldownIconsCheck", "TOPLEFT", cooldownHeader, "BOTTOMLEFT", 0, -8,
        "Show cooldown manager bars as icons (temporarily disabled)", "cooldownIconsCheck", nil
    )
    cooldownIconsCheck:SetChecked(false)
    if cooldownIconsCheck.Disable then cooldownIconsCheck:Disable() end

    ------------------------------------------------------
    -- Party Interrupt Tracker (Kick tracker)
    ------------------------------------------------------
    local kickTrackerSeparator = _MSUF_Sep(cooldownIconsCheck, -30)
    local kickTrackerHeader = _MSUF_Header(kickTrackerSeparator, "Party Interrupt Tracker")

    -- One-time warning when enabling: this tracker is best-guess (12.0 secret-safe constraints).
    local function _MSUF_ShowKickTrackerEnableWarningOnce()
        local g = EnsureGameplayDefaults()
        if not g or g.kickTrackerWarned then return end
        if not StaticPopupDialogs then
            g.kickTrackerWarned = true
            return
        end
        if not StaticPopupDialogs["MSUF_KT_ENABLE_WARN"] then
            StaticPopupDialogs["MSUF_KT_ENABLE_WARN"] = {
                text = "Party Interrupt Tracker\n\nThis is a BEST-GUESS tracker:\n• Detects PARTY interrupts via UNIT_SPELLCAST_SUCCEEDED.\n• Cooldowns are estimated from a static table (talents/resets may differ).\n• Some abilities/modifiers cannot be inspected reliably in 12.0.\n\nIf other party members also use MSUF, kicks are synced via addon messages to improve reliability.\n\nMythic+ only (party). Disabled in raid/open world.",
                button1 = OKAY,
                timeout = 0,
                whileDead = 1,
                hideOnEscape = 1,
                OnAccept = function()
                    local gg = EnsureGameplayDefaults()
                    if gg then gg.kickTrackerWarned = true end
                end,
                preferredIndex = 3,
            }
        end
        StaticPopup_Show("MSUF_KT_ENABLE_WARN")
    end


    local kickTrackerCheck = _MSUF_Check(
        "MSUF_Gameplay_KickTrackerCheck",
        "TOPLEFT", kickTrackerHeader, "BOTTOMLEFT",
        0, -8,
        "Enable party interrupt tracker",
        "kickTrackerCheck", "enableKickTracker",
        function(self, g)
            if g and g.enableKickTracker then
                _MSUF_ShowKickTrackerEnableWarningOnce()
            end
        end
    )

    local kickTrackerLockCheck = _MSUF_Check(
        "MSUF_Gameplay_KickTrackerLockCheck",
        "LEFT", kickTrackerCheck, "RIGHT",
        260, 0,
        "Lock position",
        "kickTrackerLockCheck", "lockKickTracker"
    )

    local kickTrackerWarnLabel = _MSUF_Label(
        "GameFontHighlightSmall",
        "TOPLEFT", kickTrackerCheck, "BOTTOMLEFT",
        0, -6,
        [[|cffffcc00WARNING: Best-guess tracking. Cooldowns are estimated; talents/resets may differ.
If other party members use MSUF, kicks are synced via addon messages for better accuracy.|r]],
        "kickTrackerWarnLabel"
    )
    kickTrackerWarnLabel:SetWidth(560)
    kickTrackerWarnLabel:SetJustifyH("LEFT")


    local kickTrackerShowNamesCheck = _MSUF_Check(
        "MSUF_Gameplay_KickTrackerShowNamesCheck",
        "TOPLEFT", kickTrackerWarnLabel, "BOTTOMLEFT",
        0, -6,
        "Show names",
        "kickTrackerShowNamesCheck", "kickTrackerShowNames"
    )

    local kickTrackerShowReadyCheck = _MSUF_Check(
        "MSUF_Gameplay_KickTrackerShowReadyCheck",
        "LEFT", kickTrackerShowNamesCheck, "RIGHT",
        220, 0,
        "Show READY",
        "kickTrackerShowReadyCheck", "kickTrackerShowReady"
    )


    local kickTrackerModeNote = _MSUF_Label(
        "GameFontDisableSmall",
        "TOPLEFT", kickTrackerShowNamesCheck, "BOTTOMLEFT",
        0, -6,
        "Mythic+ only (party). Optional MSUF sync via addon messages. Disabled in raid/open world (0 overhead).",
        "kickTrackerModeNote"
    )

    local kickTrackerWidthSlider = _MSUF_Slider(
        "MSUF_Gameplay_KickTrackerWidthSlider",
        "TOPLEFT", kickTrackerModeNote, "BOTTOMLEFT",
        0, -16,
        220,
        160, 420, 5,
        "160", "420",
        "Width",
        "kickTrackerWidthSlider", "kickTrackerWidth",
        function(v) return (floor((v / 5) + 0.5) * 5) end,
        nil,
        true
    )

    local kickTrackerIconSizeSlider = _MSUF_Slider(
        "MSUF_Gameplay_KickTrackerIconSizeSlider",
        "TOPLEFT", kickTrackerWidthSlider, "BOTTOMLEFT",
        0, -12,
        220,
        14, 48, 1,
        "14", "48",
        "Icon size",
        "kickTrackerIconSizeSlider", "kickTrackerIconSize",
        function(v) return floor(v + 0.5) end,
        nil,
        true
    )

    local kickTrackerSpacingSlider = _MSUF_Slider(
        "MSUF_Gameplay_KickTrackerSpacingSlider",
        "TOPLEFT", kickTrackerIconSizeSlider, "BOTTOMLEFT",
        0, -12,
        220,
        0, 18, 1,
        "0", "18",
        "Row spacing",
        "kickTrackerSpacingSlider", "kickTrackerSpacing",
        function(v) return floor(v + 0.5) end,
        nil,
        true
    )

    local kickTrackerFontSizeSlider = _MSUF_Slider(
        "MSUF_Gameplay_KickTrackerFontSizeSlider",
        "TOPLEFT", kickTrackerSpacingSlider, "BOTTOMLEFT",
        0, -12,
        220,
        8, 28, 1,
        "8", "28",
        "Font size",
        "kickTrackerFontSizeSlider", "kickTrackerFontSize",
        function(v) return floor(v + 0.5) end,
        nil,
        true
    )


    local kickTrackerBgAlphaSlider = _MSUF_Slider(
        "MSUF_Gameplay_KickTrackerBgAlphaSlider",
        "TOPLEFT", kickTrackerFontSizeSlider, "BOTTOMLEFT",
        0, -12,
        220,
        0, 1, 0.05,
        "0%", "100%",
        "Background alpha",
        "kickTrackerBgAlphaSlider", "kickTrackerBgAlpha",
        function(v) return (floor((v * 20) + 0.5) / 20) end,
        nil,
        true
    )


------------------------------------------------------
    -- Disabled/greyed state styling (match Main menu behavior)
    ------------------------------------------------------
    local function _MSUF_RememberTextColor(fs)
        if not fs or fs.__msufOrigColor then return end
        local r, g, b, a = fs:GetTextColor()

        -- Important: many Blizzard templates use a yellow default font color (GameFontNormal).
        -- For Gameplay toggles we want the "enabled" baseline to be WHITE (like the rest of MSUF),
        -- otherwise the first state refresh after a click can "lock in" yellow and spread across toggles.
        if r and g and b and (r > 0.95) and (g > 0.70) and (g < 0.95) and (b < 0.30) then
            fs.__msufOrigColor = { 1, 1, 1, a or 1 }
        else
            fs.__msufOrigColor = { r or 1, g or 1, b or 1, a or 1 }
        end
    end

    local function _MSUF_SetFontStringEnabled(fs, enabled, dimWhenOff)
        if not fs then return end
        _MSUF_RememberTextColor(fs)
        if enabled then
            local c = fs.__msufOrigColor
            fs:SetTextColor(c[1], c[2], c[3], c[4])
        else
            -- Slightly dim or strongly grey depending on context
            if dimWhenOff then
                fs:SetTextColor(0.55, 0.55, 0.55, 0.9)
            else
                fs:SetTextColor(0.45, 0.45, 0.45, 0.9)
            end
        end
    end

    local function _MSUF_SetCheckStyle(cb, forceEnabled)
        if not cb then return end
        if forceEnabled then
            cb:Enable()
        end

        local fs = cb.Text
        if not fs then return end
        _MSUF_RememberTextColor(fs)

        if not cb:IsEnabled() then
            fs:SetTextColor(0.45, 0.45, 0.45, 0.9)
            return
        end

        -- Unchecked toggles are intentionally greyed (like Main menu)
        if cb:GetChecked() then
            local c = fs.__msufOrigColor
            fs:SetTextColor(c[1], c[2], c[3], c[4])
        else
            fs:SetTextColor(0.60, 0.60, 0.60, 0.95)
        end
    end

    local function _MSUF_SetCheckEnabled(cb, enabled)
        if not cb then return end
        if enabled then
            cb:Enable()
        else
            cb:Disable()
        end
        _MSUF_SetCheckStyle(cb)
    end

    local function _MSUF_SetSliderEnabled(sl, enabled)
        if not sl then return end
        if enabled then
            sl:Enable()
        else
            sl:Disable()
        end
        sl:SetAlpha(enabled and 1 or 0.6)

        local name = sl.GetName and sl:GetName()
        if name and name ~= "" then
            _MSUF_SetFontStringEnabled(_G[name .. "Low"], enabled, true)
            _MSUF_SetFontStringEnabled(_G[name .. "High"], enabled, true)
            _MSUF_SetFontStringEnabled(_G[name .. "Text"], enabled, false)
        end
    end

    local function _MSUF_SetButtonEnabled(btn, enabled)
        if not btn then return end
        btn:SetEnabled(enabled and true or false)
        btn:SetAlpha(enabled and 1 or 0.6)
    end

local function _MSUF_SetDropdownEnabled(dd, enabled)
    if not dd then return end
    if enabled then
        if UIDropDownMenu_EnableDropDown then
            UIDropDownMenu_EnableDropDown(dd)
        elseif dd.EnableMouse then
            dd:EnableMouse(true)
        end
        if dd.SetAlpha then dd:SetAlpha(1) end
    else
        if UIDropDownMenu_DisableDropDown then
            UIDropDownMenu_DisableDropDown(dd)
        elseif dd.EnableMouse then
            dd:EnableMouse(false)
        end
        if dd.SetAlpha then dd:SetAlpha(0.6) end
    end
end

    local function _MSUF_SetEditBoxEnabled(eb, enabled)
        if not eb then return end
        if not enabled and eb.ClearFocus then
            eb:ClearFocus()
        end

        if eb.EnableMouse then
            eb:EnableMouse(enabled and true or false)
        end
        if eb.SetAlpha then
            eb:SetAlpha(enabled and 1 or 0.6)
        end

        -- Text color + visual dim
        if eb.SetTextColor then
            if enabled then
                eb:SetTextColor(1, 1, 1, 1)
            else
                eb:SetTextColor(0.65, 0.65, 0.65, 0.95)
            end
        end
    end

    function panel:MSUF_UpdateGameplayDisabledStates()
        local g = EnsureGameplayDefaults()

        -- Top-level toggles: always enabled, but unchecked is greyed
        _MSUF_SetCheckStyle(self.combatTimerCheck, true)
        _MSUF_SetCheckStyle(self.combatStateCheck, true)
        _MSUF_SetCheckStyle(self.combatCrosshairCheck, true)
        _MSUF_SetCheckStyle(self.cooldownIconsCheck, false)
        _MSUF_SetCheckStyle(self.kickTrackerCheck, true)

        -- Combat Timer dependents
        local timerOn = g.enableCombatTimer and true or false
        _MSUF_SetSliderEnabled(self.combatFontSizeSlider, timerOn)
        _MSUF_SetCheckEnabled(self.lockCombatTimerCheck, timerOn)
        _MSUF_SetFontStringEnabled(self.combatTimerAnchorLabel, timerOn, false)
        _MSUF_SetDropdownEnabled(self.combatTimerAnchorDropdown, timerOn)

        -- Combat Enter/Leave dependents
        local stateOn = g.enableCombatStateText and true or false
        _MSUF_SetFontStringEnabled(self.combatStateEnterLabel, stateOn, false)
        _MSUF_SetFontStringEnabled(self.combatStateLeaveLabel, stateOn, false)
        _MSUF_SetEditBoxEnabled(self.combatStateEnterInput, stateOn)
        _MSUF_SetEditBoxEnabled(self.combatStateLeaveInput, stateOn)
        _MSUF_SetSliderEnabled(self.combatStateFontSizeSlider, stateOn)
        _MSUF_SetSliderEnabled(self.combatStateDurationSlider, stateOn)
        _MSUF_SetCheckEnabled(self.lockCombatStateCheck, stateOn)
        _MSUF_SetButtonEnabled(self.combatStateDurationResetButton, stateOn)

        -- Rogue: First Dance is a Rogue-only helper (independent of the Enter/Leave text toggle).
        local isRogue = false
        if UnitClass then
            local _, class = UnitClass("player")
            isRogue = (class == "ROGUE")
        end
        _MSUF_SetCheckEnabled(self.firstDanceCheck, isRogue)

        -- Shaman: Player Totems dependents
        local isShaman = false
        if UnitClass then
            local _, class = UnitClass("player")
            isShaman = (class == "SHAMAN")
        end

        -- Enable toggle itself is only relevant for Shaman
        _MSUF_SetCheckEnabled(self.playerTotemsCheck, isShaman)

        _MSUF_SetButtonEnabled(self.playerTotemsPreviewButton, isShaman)


        local kickTrackerOn = g.enableKickTracker and true or false
        _MSUF_SetCheckEnabled(self.kickTrackerLockCheck, kickTrackerOn)
        _MSUF_SetCheckEnabled(self.kickTrackerShowNamesCheck, kickTrackerOn)
        _MSUF_SetCheckEnabled(self.kickTrackerShowReadyCheck, kickTrackerOn)
                _MSUF_SetSliderEnabled(self.kickTrackerWidthSlider, kickTrackerOn)
        _MSUF_SetSliderEnabled(self.kickTrackerIconSizeSlider, kickTrackerOn)
        _MSUF_SetSliderEnabled(self.kickTrackerSpacingSlider, kickTrackerOn)
        _MSUF_SetSliderEnabled(self.kickTrackerFontSizeSlider, kickTrackerOn)

        _MSUF_SetSliderEnabled(self.kickTrackerBgAlphaSlider, kickTrackerOn)
        local previewActive = (ns and ns.MSUF_PlayerTotems_IsPreviewActive and ns.MSUF_PlayerTotems_IsPreviewActive()) and true or false
        local totemsOn = (isShaman and (g.enablePlayerTotems or previewActive)) and true or false
        _MSUF_SetCheckEnabled(self.playerTotemsShowTextCheck, totemsOn)
        _MSUF_SetCheckEnabled(self.playerTotemsScaleByIconCheck, (totemsOn and g.playerTotemsShowText) and true or false)

        _MSUF_SetSliderEnabled(self.playerTotemsIconSizeSlider, totemsOn)
        _MSUF_SetSliderEnabled(self.playerTotemsSpacingSlider, totemsOn)
        _MSUF_SetSliderEnabled(self.playerTotemsOffsetXSlider, totemsOn)
        _MSUF_SetSliderEnabled(self.playerTotemsOffsetYSlider, totemsOn)

        _MSUF_SetDropdownEnabled(self.playerTotemsGrowthDropdown, totemsOn)
        _MSUF_SetButtonEnabled(self.playerTotemsAnchorFromButton, totemsOn)
        _MSUF_SetButtonEnabled(self.playerTotemsAnchorToButton, totemsOn)
        local textOn = (totemsOn and g.playerTotemsShowText) and true or false
        local canManualFont = (textOn and not g.playerTotemsScaleTextByIconSize) and true or false
        _MSUF_SetSliderEnabled(self.playerTotemsFontSizeSlider, canManualFont)

        if self.playerTotemsColorSwatch then
            if self.playerTotemsColorSwatch.SetAlpha then
                self.playerTotemsColorSwatch:SetAlpha(textOn and 1 or 0.6)
            end
            if self.playerTotemsColorSwatch.EnableMouse then
                self.playerTotemsColorSwatch:EnableMouse(textOn and true or false)
            end
        end

                if self.playerTotemsPreviewButton and self.playerTotemsPreviewButton.SetText then
            local active = (ns and ns.MSUF_PlayerTotems_IsPreviewActive and ns.MSUF_PlayerTotems_IsPreviewActive()) and true or false
            self.playerTotemsPreviewButton:SetText(active and "Stop preview" or "Preview")
        end

-- Crosshair dependents
        local crosshairOn = g.enableCombatCrosshair and true or false
        _MSUF_SetCheckEnabled(self.crosshairRangeColorCheck, crosshairOn)
        _MSUF_SetFontStringEnabled(self.crosshairRangeHintText, crosshairOn, true)
        _MSUF_SetFontStringEnabled(self.crosshairThicknessLabel, crosshairOn, false)
        _MSUF_SetFontStringEnabled(self.crosshairSizeLabel, crosshairOn, false)
        _MSUF_SetSliderEnabled(self.crosshairThicknessSlider, crosshairOn)
        _MSUF_SetSliderEnabled(self.crosshairSizeSlider, crosshairOn)

        -- Spell selection is only relevant when range-color mode is active
        local rangeOn = (crosshairOn and g.enableCombatCrosshairMeleeRangeColor) and true or false
        _MSUF_SetFontStringEnabled(self.meleeSharedTitle, rangeOn, false)
        _MSUF_SetFontStringEnabled(self.meleeSharedSubText, rangeOn, true)
        _MSUF_SetFontStringEnabled(self.meleeSpellChooseLabel, rangeOn, true)
        _MSUF_SetFontStringEnabled(self.meleeSpellSelectedText, rangeOn, true)
        _MSUF_SetFontStringEnabled(self.meleeSpellUsedByText, rangeOn, true)
        _MSUF_SetEditBoxEnabled(self.meleeSpellInput, rangeOn)
        _MSUF_SetCheckEnabled(self.meleeSpellPerClassCheck, rangeOn)
        _MSUF_SetFontStringEnabled(self.meleeSpellPerClassHint, rangeOn, true)

        if self.meleeSuggestionFrame and not rangeOn then
            self.meleeSuggestionFrame:Hide()
        end

        -- Keep the orange warning aligned with enabled state
        if UpdateSelectedTextFromDB then
            UpdateSelectedTextFromDB()
        end

        if self.MSUF_UpdateCrosshairPreview then
            self.MSUF_UpdateCrosshairPreview()
        end
    end

    lastControl = kickTrackerBgAlphaSlider

    ------------------------------------------------------
    -- Panel scripts (refresh/okay/default)
    ------------------------------------------------------

    -- Reset all gameplay option keys to their default values.
    -- We do this by nil-ing the keys and then re-running EnsureGameplayDefaults(),
    -- which repopulates defaults in one place (single source of truth).
    local _MSUF_GAMEPLAY_DEFAULT_KEYS = {
        "nameplateMeleeSpellID",
        "meleeSpellPerClass",
        "nameplateMeleeSpellIDByClass",

        "combatOffsetX",
        "combatOffsetY",
        "combatTimerAnchor",
        "combatFontSize",
        "enableCombatTimer",
        "lockCombatTimer",

        "combatStateOffsetX",
        "combatStateOffsetY",
        "combatStateFontSize",
        "combatStateDuration",
        "enableCombatStateText",
        "combatStateEnterText",
        "combatStateLeaveText",
        "lockCombatState",

        "enableFirstDanceTimer",

        "enablePlayerTotems",
        "playerTotemsShowText",
        "playerTotemsScaleTextByIconSize",
        "playerTotemsIconSize",
        "playerTotemsSpacing",
        "playerTotemsAnchorFrom",
        "playerTotemsAnchorTo",
        "playerTotemsGrowthDirection",
        "playerTotemsOffsetX",
        "playerTotemsOffsetY",
        "playerTotemsFontSize",
        "playerTotemsTextColor",

        "enableCombatCrosshair",
        "enableCombatCrosshairMeleeRangeColor",
        "crosshairThickness",
        "crosshairSize",

        "cooldownIcons",

        "enableKickTracker",
        "lockKickTracker",
        "kickTrackerOffsetX",
        "kickTrackerOffsetY",
        "kickTrackerWidth",
        "kickTrackerIconSize",
        "kickTrackerSpacing",
        "kickTrackerFontSize",
        "kickTrackerShowNames",
        "kickTrackerShowReady",
        "kickTrackerShowInDungeon",
        "kickTrackerShowInOpenWorld",
        "kickTrackerShowInRaid",


    }

    local function _MSUF_ResetGameplayToDefaults()
        local g = EnsureGameplayDefaults()
        for i = 1, #_MSUF_GAMEPLAY_DEFAULT_KEYS do
            g[_MSUF_GAMEPLAY_DEFAULT_KEYS[i]] = nil
        end
        return EnsureGameplayDefaults()
    end

    local function _MSUF_Clamp(v, lo, hi)
        if v == nil then return lo end
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    panel.refresh = function(self)
        self._msufSuppressSliderChanges = true
        local g = EnsureGameplayDefaults()

        -- Melee spell selection (shared)
        local meleeInput = self.meleeSpellInput
        if meleeInput then
            local id = 0
            if g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
                local _, class = UnitClass("player")
                if class then
                    id = tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0
                end
            end
            if id <= 0 then
                id = tonumber(g.nameplateMeleeSpellID) or 0
            end
            meleeInput:SetText((id > 0) and tostring(id) or "")
        end

        if self.meleeSpellPerClassCheck then
            self.meleeSpellPerClassCheck:SetChecked(g.meleeSpellPerClass and true or false)
        end
        if UpdateSelectedTextFromDB then
            UpdateSelectedTextFromDB()
        end

        local function SetCheck(field, key, notFalse)
            local cb = self[field]
            if not cb then return end
            local v = notFalse and (g[key] ~= false) or (g[key] and true or false)
            cb:SetChecked(v)
        end

        local function SetSlider(field, key, default)
            local sl = self[field]
            if not sl then return end
            sl:SetValue(tonumber(g[key]) or default or 0)
        end

        -- Simple checks
        local checks = {
            {"combatTimerCheck", "enableCombatTimer"},
            {"lockCombatTimerCheck", "lockCombatTimer"},

            {"combatStateCheck", "enableCombatStateText"},
            {"lockCombatStateCheck", "lockCombatState"},

            {"firstDanceCheck", "enableFirstDanceTimer"},

            {"playerTotemsCheck", "enablePlayerTotems"},
            {"playerTotemsShowTextCheck", "playerTotemsShowText"},
            {"playerTotemsScaleByIconCheck", "playerTotemsScaleTextByIconSize"},

            {"combatCrosshairCheck", "enableCombatCrosshair"},
            {"crosshairRangeColorCheck", "enableCombatCrosshairMeleeRangeColor"},

            {"cooldownIconsCheck", "cooldownIcons", true},
            {"kickTrackerCheck", "enableKickTracker", true},
            {"kickTrackerLockCheck", "lockKickTracker", true},
            {"kickTrackerShowNamesCheck", "kickTrackerShowNames", true},
            {"kickTrackerShowReadyCheck", "kickTrackerShowReady", true},
        }
        for i = 1, #checks do
            local t = checks[i]
            SetCheck(t[1], t[2], t[3])
        end

        -- Simple sliders
        local sliders = {
            {"combatFontSizeSlider", "combatFontSize", 0},
            {"combatStateFontSizeSlider", "combatStateFontSize", 0},
            {"combatStateDurationSlider", "combatStateDuration", 1.5},

            {"playerTotemsIconSizeSlider", "playerTotemsIconSize", 24},
            {"playerTotemsSpacingSlider", "playerTotemsSpacing", 4},
            {"playerTotemsFontSizeSlider", "playerTotemsFontSize", 14},
            {"playerTotemsOffsetXSlider", "playerTotemsOffsetX", 0},
            {"playerTotemsOffsetYSlider", "playerTotemsOffsetY", -6},
            {"kickTrackerWidthSlider", "kickTrackerWidth", 220},
            {"kickTrackerIconSizeSlider", "kickTrackerIconSize", 26},
            {"kickTrackerSpacingSlider", "kickTrackerSpacing", 4},
            {"kickTrackerFontSizeSlider", "kickTrackerFontSize", 14},

            {"kickTrackerBgAlphaSlider", "kickTrackerBgAlpha", 0.35},
        }
        for i = 1, #sliders do
            local t = sliders[i]
            SetSlider(t[1], t[2], t[3])
        end

        -- Combat Timer anchor dropdown
        if self.combatTimerAnchorDropdown then
            local v = g.combatTimerAnchor
            if v ~= "none" and v ~= "player" and v ~= "target" and v ~= "focus" then
                v = "none"
            end
            local txt
            if v == "player" then txt = "Player"
            elseif v == "target" then txt = "Target"
            elseif v == "focus" then txt = "Focus"
            else txt = "None" end
            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self.combatTimerAnchorDropdown, v) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self.combatTimerAnchorDropdown, txt) end
        end

        -- Combat state texts
        local eb = self.combatStateEnterInput
        if eb then
            local v = g.combatStateEnterText
            eb:SetText((type(v) == "string") and v or "+Combat")
        end

        eb = self.combatStateLeaveInput
        if eb then
            local v = g.combatStateLeaveText
            eb:SetText((type(v) == "string") and v or "-Combat")
        end

        -- Crosshair special values (clamped)
        local sl = self.crosshairThicknessSlider
        if sl then
            local t = tonumber(g.crosshairThickness) or 2
            sl:SetValue(_MSUF_Clamp(math.floor(t + 0.5), 1, 10))
        end

        sl = self.crosshairSizeSlider
        if sl then
            local v = tonumber(g.crosshairSize) or 40
            sl:SetValue(_MSUF_Clamp(math.floor(v + 0.5), 20, 80))
        end

        if self.MSUF_UpdateCrosshairPreview then
            self.MSUF_UpdateCrosshairPreview()
        end
        if self.playerTotemsGrowthDropdown then
            local growth = g.playerTotemsGrowthDirection
            if growth ~= "LEFT" and growth ~= "RIGHT" and growth ~= "UP" and growth ~= "DOWN" then
                growth = "RIGHT"
            end
            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self.playerTotemsGrowthDropdown, growth) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self.playerTotemsGrowthDropdown, growth) end
        end

        if self.playerTotemsAnchorFromButton and self.playerTotemsAnchorFromButton.SetText then
            local af = g.playerTotemsAnchorFrom
            if type(af) ~= "string" or af == "" then
                af = "TOPLEFT"
            end
            self.playerTotemsAnchorFromButton:SetText("From: " .. af)
        end

        if self.playerTotemsAnchorToButton and self.playerTotemsAnchorToButton.SetText then
            local at = g.playerTotemsAnchorTo
            if type(at) ~= "string" or at == "" then
                at = "BOTTOMLEFT"
            end
            self.playerTotemsAnchorToButton:SetText("To: " .. at)
        end
        if self.playerTotemsColorSwatch and self.playerTotemsColorSwatch.MSUF_Refresh then
            self.playerTotemsColorSwatch:MSUF_Refresh()
        end
        -- Grey out dependent controls when their parent toggle is off
        if self.MSUF_UpdateGameplayDisabledStates then
            self:MSUF_UpdateGameplayDisabledStates()
        end

        -- Done syncing; re-enable bindings.
        self._msufSuppressSliderChanges = false
    end

-- Live-sync: allow the Totem preview frame to drag-update X/Y without spamming Apply().
function panel:MSUF_SyncTotemOffsetSliders()
    if not self.playerTotemsOffsetXSlider or not self.playerTotemsOffsetYSlider then
        return
    end
    local g = EnsureGameplayDefaults()
    self._msufSuppressSliderChanges = true
    self.playerTotemsOffsetXSlider:SetValue(tonumber(g.playerTotemsOffsetX) or 0)
    self.playerTotemsOffsetYSlider:SetValue(tonumber(g.playerTotemsOffsetY) or -6)
    self._msufSuppressSliderChanges = false
end

    -- Most controls apply immediately, but "Okay" is still called by the Settings/Interface panel system.
    -- We use it as a safe "finalize" hook.
    panel.okay = function(self)
        if self.meleeSpellInput and self.meleeSpellInput.HasFocus and self.meleeSpellInput:HasFocus() then
            self.meleeSpellInput:ClearFocus()
        end

        ns.MSUF_RequestGameplayApply()

        if ns and ns.MSUF_RequestCooldownIconsSync then
            ns.MSUF_RequestCooldownIconsSync()
        elseif MSUF_ApplyCooldownIconMode then
            MSUF_ApplyCooldownIconMode()
        end
    end

    panel.default = function(self)
        _MSUF_ResetGameplayToDefaults()
        if self.refresh then
            self:refresh()
        end

        ns.MSUF_RequestGameplayApply()

        if ns and ns.MSUF_RequestCooldownIconsSync then
            ns.MSUF_RequestCooldownIconsSync()
        elseif MSUF_ApplyCooldownIconMode then
            MSUF_ApplyCooldownIconMode()
        end
    end

    
    ------------------------------------------------------
    -- Dynamic content height
    ------------------------------------------------------
    local function UpdateContentHeight()
        local minHeight = 400
        if not lastControl then
            content:SetHeight(minHeight)
            return
        end

        local bottom = lastControl:GetBottom()
        local top    = content:GetTop()
        if not bottom or not top then
            content:SetHeight(minHeight)
            return
        end

        local padding = 40
        local height  = top - bottom + padding
        if height < minHeight then
            height = minHeight
        end
        content:SetHeight(height)
    end

    panel:SetScript("OnShow", function()
        if _G.MSUF_StyleAllToggles then _G.MSUF_StyleAllToggles(panel) end
        if panel.refresh then
            panel:refresh()
        end
        UpdateContentHeight()
    end)

-- Settings registration
    if (not panel.__MSUF_SettingsRegistered) and Settings and Settings.RegisterCanvasLayoutSubcategory and parentCategory then
        local subcategory, layout = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
        Settings.RegisterAddOnCategory(subcategory)
        panel.__MSUF_SettingsRegistered = true
        ns.MSUF_GameplayCategory = subcategory
    elseif InterfaceOptions_AddCategory then
        panel.parent = "Midnight Simple Unit Frames"
        InterfaceOptions_AddCategory(panel)
    end

    -- Beim Ã–ffnen des Panels SavedVariables â†’ UI syncen
    panel:refresh()
    UpdateContentHeight()

    if _G.MSUF_StyleAllToggles then _G.MSUF_StyleAllToggles(panel) end

    -- Und aktuelle Visuals anwenden
    ns.MSUF_RequestGameplayApply()

    panel.__MSUF_GameplayBuilt = true
    return panel
end

-- Lightweight wrapper: register the category at login, but build the heavy UI only when opened.
function ns.MSUF_RegisterGameplayOptions(parentCategory)
    if not Settings or not Settings.RegisterCanvasLayoutSubcategory or not parentCategory then
        -- Fallback: if Settings API isn't available, just build immediately.
        return ns.MSUF_RegisterGameplayOptions_Full(parentCategory)
    end

    local panel = (_G and _G.MSUF_GameplayPanel) or CreateFrame("Frame", "MSUF_GameplayPanel", UIParent)
    panel.name = "Gameplay"

    -- IMPORTANT: Panels created with UIParent are shown by default.
    -- If we rely on OnShow for first-time build, we must ensure the panel starts hidden,
    -- otherwise the first Settings click may not fire OnShow.
    if not panel.__MSUF_ForceHidden then
        panel.__MSUF_ForceHidden = true
        panel:Hide()
    end

    -- Register the subcategory now (cheap) so it shows up immediately in Settings.
    if not panel.__MSUF_SettingsRegistered then
        local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
        Settings.RegisterAddOnCategory(subcategory)
        ns.MSUF_GameplayCategory = subcategory
        panel.__MSUF_SettingsRegistered = true
    end

    -- Already built: nothing else to do.
    if panel.__MSUF_GameplayBuilt then
        return panel
    end

    -- First open builds the full panel. Build synchronously in OnShow so the panel is ready on the first click.

    if not panel.__MSUF_LazyBuildHooked then

        panel.__MSUF_LazyBuildHooked = true

    

        panel:HookScript("OnShow", function()

            if panel.__MSUF_GameplayBuilt or panel.__MSUF_GameplayBuilding then

                return

            end

            panel.__MSUF_GameplayBuilding = true

    

            -- Build immediately (no C_Timer.After(0)): avoids "needs second click" issues.

            ns.MSUF_RegisterGameplayOptions_Full(parentCategory)

    

            panel.__MSUF_GameplayBuilding = nil

        end)

    end

    

    return panel

    end

------------------------------------------------------
-- Auto-apply Gameplay features on load
-- Fixes: after /reload or relog, Combat Enter/Leave text (and other Gameplay
-- features) could be "enabled" in the UI but not actually active until the
-- checkbox was toggled in the Gameplay menu.
------------------------------------------------------
do
    local didApply = false

    local function AutoApplyOnce()
        if didApply then return end
        didApply = true

        -- Export a global helper so core can force-apply after autoloading this LoD addon.
        if type(ns.MSUF_RequestGameplayApply) == "function" then
            _G.MSUF_RequestGameplayApply = ns.MSUF_RequestGameplayApply
        end
        if type(EnsureGameplayDefaults) == "function" then
            EnsureGameplayDefaults()
        end

        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
    end

    -- Run next tick so SavedVariables + UpdateManager are ready,
    -- even when this LoD file is loaded mid-session.
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, AutoApplyOnce)
    else
        AutoApplyOnce()
    end

    -- Also hook common init events in case of unusual load order.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        AutoApplyOnce()
        f:UnregisterAllEvents()
        f:SetScript("OnEvent", nil)
    end)
end
