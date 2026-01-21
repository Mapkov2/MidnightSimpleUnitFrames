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
local function MSUF_GetUpdateManager()
    return _G.MSUF_UpdateManager or (ns and ns.MSUF_UpdateManager)
end

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
-- One-time tip popup: gameplay colors live in Colors → Gameplay
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
        fontPath = "Fonts\\FRIZQT__.TTF"
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
local combatTimerEventFrame
local combatStateFrame
local combatStateText
local combatEventFrame
local combatCrosshairFrame
local combatCrosshairEventFrame
local updater

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
        combatTimerText:SetFont(path or "Fonts\\FRIZQT__.TTF", size or 20, flags or "OUTLINE")
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
        combatStateText:SetFont(path or "Fonts\\FRIZQT__.TTF", (size or 24), flags or "OUTLINE")
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
        firstDanceActive = false
        firstDanceEndTime = 0
        firstDanceLastText = nil
        local umFD = MSUF_GetUpdateManager()
        if umFD and umFD.SetEnabled then
            umFD:SetEnabled("MSUF_GAMEPLAY_FIRSTDANCE", false)
        end
        MSUF_CombatState_SetClickThrough(false)
        return
    end

    if not combatStateText and EnsureCombatStateText then
        EnsureCombatStateText()
    end

    if not combatStateText then
        local umFD = MSUF_GetUpdateManager()
        if umFD and umFD.SetEnabled then
            umFD:SetEnabled("MSUF_GAMEPLAY_FIRSTDANCE", false)
        end
        MSUF_CombatState_SetClickThrough(false)
        return
    end

    firstDanceEndTime = GetTime() + FIRST_DANCE_WINDOW
    firstDanceActive = true
    firstDanceLastText = nil

    -- Make sure font / shadow are up to date
    local path, flags, r, gCol, bCol, size, useShadow = GetGameplayFontSettings("state")
    combatStateText:SetFont(path or "Fonts\\FRIZQT__.TTF", (size or 24), flags or "OUTLINE")
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

    -- Ensure the First Dance tick task exists even if this triggers before a full Apply() pass.
    if EnsureFirstDanceTaskRegistered then
        EnsureFirstDanceTaskRegistered()
    end

    local umFD = MSUF_GetUpdateManager()
    if umFD and umFD.SetEnabled then
        umFD:SetEnabled("MSUF_GAMEPLAY_FIRSTDANCE", true)
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
    combatStateText:SetFont(path or "Fonts\\FRIZQT__.TTF", (size or 24), flags or "OUTLINE")
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
        combatEventFrame = CreateFrame("Frame", "MSUF_CombatStateEventFrame", UIParent)
        -- Events are registered/unregistered in ns.MSUF_RequestGameplayApply() for performance.
        combatEventFrame:UnregisterAllEvents()
local function MSUF_CombatState_OnEvent(_, event)
    local g = GetGameplayDBFast()
    if not g or (not g.enableCombatStateText and not g.enableFirstDanceTimer) then
        if combatStateText then
            combatStateText:SetText("")
            combatStateText:Hide()
            MSUF_CombatState_SetClickThrough(false)
        end
        MSUF_CombatState_SetClickThrough(false)
        -- Always hard-stop First Dance if feature is disabled
        firstDanceActive = false
        firstDanceEndTime = 0
        firstDanceLastText = nil
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
        firstDanceActive = false
        firstDanceEndTime = 0
        firstDanceLastText = nil

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
        firstDanceActive = false
        firstDanceEndTime = 0
        firstDanceLastText = nil

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
combatEventFrame:SetScript("OnEvent", MSUF_CombatState_OnEvent)
    end

end

------------------------------------------------------
-- "First Dance" countdown tick
------------------------------------------------------
local function _TickFirstDance()
    if not firstDanceActive then
        return
    end

    local gFD = GetGameplayDBFast()
    if not gFD.enableFirstDanceTimer then
        firstDanceActive = false
        firstDanceEndTime = 0
        firstDanceLastText = nil
        if combatStateText then
            combatStateText:SetText("")
            combatStateText:Hide()
        end
        MSUF_CombatState_SetClickThrough(false)
        local umFD = MSUF_GetUpdateManager()
        if umFD and umFD.SetEnabled then
            umFD:SetEnabled("MSUF_GAMEPLAY_FIRSTDANCE", false)
        end
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
        firstDanceActive = false
        firstDanceEndTime = 0
        firstDanceLastText = nil
        combatStateText:SetText("")
        combatStateText:Hide()
        MSUF_CombatState_SetClickThrough(false)
        local umFD = MSUF_GetUpdateManager()
        if umFD and umFD.SetEnabled then
            umFD:SetEnabled("MSUF_GAMEPLAY_FIRSTDANCE", false)
        end
        return
    end

    local text = string_format("First Dance: %.1f", remaining)
    if text ~= firstDanceLastText then
        firstDanceLastText = text
        combatStateText:SetText(text)
    end
end


EnsureFirstDanceTaskRegistered = function()
    if ns and ns._MSUF_FirstDanceTaskRegistered then
        return
    end
    if not combatStateFrame then
        return
    end

    local umFD = MSUF_GetUpdateManager()
    if umFD and umFD.Register and umFD.SetEnabled then
        if ns then
            ns._MSUF_FirstDanceTaskRegistered = true
        end
        umFD:Register("MSUF_GAMEPLAY_FIRSTDANCE", _TickFirstDance, 0.10)  -- 10Hz is plenty
        umFD:SetEnabled("MSUF_GAMEPLAY_FIRSTDANCE", false)

        -- Ensure no leftover per-frame updater stays attached
        combatStateFrame:SetScript("OnUpdate", nil)
    else
        -- Fallback: local OnUpdate if UpdateManager isn't available
        if ns then
            ns._MSUF_FirstDanceTaskRegistered = true
        end
        combatStateFrame:SetScript("OnUpdate", function(self, elapsed)
            _TickFirstDance()
        end)
    end
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
        -- Zusätzliche Flags
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

    -- Wenn Blizzard-Selfhighlight / Nameplates aktiv sind → an persönliche
    -- Nameplate hängen und den Offset abhängig vom Zoom berechnen.
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
                elseif event == "PLAYER_TARGET_CHANGED" then
                    MSUF_RequestCrosshairRangeRefresh()
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

        -- Range color tick: prefer MSUF_UpdateManager (single global OnUpdate) and
-- fall back to a local throttled OnUpdate if needed.
local umRange = MSUF_GetUpdateManager()
if umRange and umRange.Register and umRange.SetEnabled then
    if not ns._MSUF_CrosshairRangeTaskRegistered then
        ns._MSUF_CrosshairRangeTaskRegistered = true
        umRange:Register("MSUF_GAMEPLAY_CROSSHAIR_RANGE", function()
            if not combatCrosshairFrame or not combatCrosshairFrame:IsShown() then
                return
            end

            -- No DB reads in the hotpath: rely on cached flags/spellID from Apply.
            if not combatCrosshairFrame._msufUseRangeColor or (combatCrosshairFrame._msufRangeSpellID or 0) <= 0 then
                -- Neutralize and stop ticking until config becomes valid again
                MSUF_UpdateCombatCrosshairRangeColor()
                umRange:SetEnabled("MSUF_GAMEPLAY_CROSSHAIR_RANGE", false)
                return
            end

            if not MSUF_CrosshairHasValidTarget() then
                -- No valid target: revert to neutral and stop the background tick until a new target appears
                MSUF_UpdateCombatCrosshairRangeColor()
                umRange:SetEnabled("MSUF_GAMEPLAY_CROSSHAIR_RANGE", false)
                return
            end

            MSUF_UpdateCombatCrosshairRangeColor()
        end, function()
            return (combatCrosshairFrame and combatCrosshairFrame._msufRangeTickInterval) or 0.25
        end)
        umRange:SetEnabled("MSUF_GAMEPLAY_CROSSHAIR_RANGE", false)
    end

        MSUF_RefreshCrosshairRangeTaskEnabled()

    -- Kill any older per-frame updater we may have had
    if combatCrosshairFrame.MSUF_RangeOnUpdate then
        combatCrosshairFrame:SetScript("OnUpdate", nil)
        combatCrosshairFrame.MSUF_RangeOnUpdate = nil
        combatCrosshairFrame.MSUF_RangeElapsed = nil
    end
else
    -- Legacy fallback: local throttled OnUpdate to keep range color responsive while moving
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

    end

    return combatCrosshairFrame
end

-- Lock / unlock helper
local function ApplyLockState()
    local g = EnsureGameplayDefaults()
    if combatFrame then
        if g.lockCombatTimer then
            combatFrame:EnableMouse(false)
        else
            combatFrame:EnableMouse(true)
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
    combatFrame:SetPoint("CENTER", UIParent, "CENTER", g.combatOffsetX, g.combatOffsetY)
    combatFrame:SetFrameStrata("DIALOG")
    combatFrame:SetClampedToScreen(true)
    combatFrame:SetMovable(true)
    combatFrame:RegisterForDrag("LeftButton")

    combatFrame:SetScript("OnDragStart", function(self)
        local gd = EnsureGameplayDefaults()
        if gd.lockCombatTimer then
            return
        end
        self:StartMoving()
    end)

    combatFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local uiX, uiY = UIParent:GetCenter()
        local dx = x - uiX
        local dy = y - uiY
        local db = EnsureGameplayDefaults()
        db.combatOffsetX = dx
        db.combatOffsetY = dy
    end)

    combatTimerText = combatFrame:CreateFontString(nil, "OVERLAY")
    combatTimerText:SetPoint("CENTER")

    -- very important: set font BEFORE any SetText call
    ApplyFontToCounter()
    combatTimerText:SetText("")

    -- Apply initial lock state
    ApplyLockState()

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
local MSUF_MeleeSpellCacheEventFrame

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
        if not MSUF_MeleeSpellCacheEventFrame then
            MSUF_MeleeSpellCacheEventFrame = CreateFrame("Frame", "MSUF_MeleeSpellCacheEventFrame", UIParent)
            local function MSUF_MeleeSpellCache_OnEvent()
                if not MSUF_MeleeSpellCachePending then
                    return
                end
                MSUF_MeleeSpellCachePending = false
                MSUF_MeleeSpellCacheEventFrame:UnregisterAllEvents()
                MSUF_BuildMeleeSpellCache()
            end
            MSUF_MeleeSpellCacheEventFrame:SetScript("OnEvent", MSUF_MeleeSpellCache_OnEvent)

        end
        MSUF_MeleeSpellCacheEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
        if MSUF_MeleeSpellCacheEventFrame then
            MSUF_MeleeSpellCacheEventFrame:UnregisterAllEvents()
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
    local um = MSUF_GetUpdateManager()
    if um and um.SetEnabled then
        um:SetEnabled("MSUF_GAMEPLAY_CROSSHAIR_RANGE", enabled and true or false)
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
            firstDanceActive = false
            firstDanceEndTime = 0
            firstDanceLastText = nil
            local umFD = MSUF_GetUpdateManager()
            if umFD and umFD.SetEnabled then
                umFD:SetEnabled("MSUF_GAMEPLAY_FIRSTDANCE", false)
            end
        end

        -- Ensure the frame is draggable again when configuring / previewing
        MSUF_CombatState_SetClickThrough(false)

        -- We need combat regen events for BOTH: enter/leave text + first dance window start.
        if combatEventFrame then
            combatEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            combatEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
        if combatEventFrame then
            combatEventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
            combatEventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end

        firstDanceActive = false
        firstDanceEndTime = 0
        firstDanceLastText = nil
        local umFD = MSUF_GetUpdateManager()
        if umFD and umFD.SetEnabled then
            umFD:SetEnabled("MSUF_GAMEPLAY_FIRSTDANCE", false)
        end
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
            combatCrosshairEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
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

        -- Off means off: stop any range-color background task too
        local umRange = MSUF_GetUpdateManager()
        if umRange and umRange.SetEnabled then
            umRange:SetEnabled("MSUF_GAMEPLAY_CROSSHAIR_RANGE", false)
        end

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


-- Feature tables (single-file modules) for readability and safer future refactors
local GameplayFeatures = {
    CombatTimer     = {},
    CombatStateText = {},
    CombatCrosshair = {},
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
        combatFrame:SetShown(g.enableCombatTimer)
    end
end

GameplayFeatures.CombatStateText.Apply = MSUF_Gameplay_ApplyCombatStateText
GameplayFeatures.CombatCrosshair.Apply = MSUF_Gameplay_ApplyCombatCrosshair

local GameplayFeatureOrder = { "CombatTimer", "CombatStateText", "CombatCrosshair" }

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

-- Centralized throttling: register combat-timer ticks in the global MSUF_UpdateManager
    local um = MSUF_GetUpdateManager()
    if um and um.Register and um.SetEnabled then
        if not ns._MSUF_GameplayTasksRegistered then
            ns._MSUF_GameplayTasksRegistered = true

            local function _CombatInterval()
                -- Timer is formatted as mm:ss, so it only changes once per second.
                -- Keeping this at 1.0s reduces CPU in raids without any visible downside.
                return 1.0
            end
            um:Register("MSUF_GAMEPLAY_COMBATTIMER", MSUF_Gameplay_TickCombatTimer, _CombatInterval, 90)
        end

        -- Off means off: enable only what is configured
        um:SetEnabled("MSUF_GAMEPLAY_COMBATTIMER", g.enableCombatTimer and true or false)

        -- Make combat timer start immediately on combat start (no 0-1s "lag").
        -- We also set combatStartTime from the event timestamp so the timer isn't permanently behind.
        if not combatTimerEventFrame then
            combatTimerEventFrame = CreateFrame("Frame", "MSUF_CombatTimerEventFrame", UIParent)
            combatTimerEventFrame:SetScript("OnEvent", function(_, event)
                local gd = GetGameplayDBFast()
                if not gd or not gd.enableCombatTimer then
                    return
                end

                if event == "PLAYER_REGEN_DISABLED" then
                    combatStartTime = GetTime()
                    wasInCombat = true
                    -- Force a refresh even if text would be the same.
                    lastTimerText = ""
                    MSUF_Gameplay_TickCombatTimer()
                elseif event == "PLAYER_REGEN_ENABLED" then
                    wasInCombat = false
                    combatStartTime = nil
                    lastTimerText = ""
                    MSUF_Gameplay_TickCombatTimer()
                elseif event == "PLAYER_ENTERING_WORLD" then
                    -- Safety reset on zoning/loading screens.
                    lastTimerText = ""
                    if UnitAffectingCombat and UnitAffectingCombat("player") then
                        if not combatStartTime then
                            combatStartTime = GetTime()
                        end
                        wasInCombat = true
                    else
                        wasInCombat = false
                        combatStartTime = nil
                    end
                    MSUF_Gameplay_TickCombatTimer()
                end
            end)
        end

        combatTimerEventFrame:UnregisterAllEvents()
        if g.enableCombatTimer then
            combatTimerEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            combatTimerEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            combatTimerEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

            -- If the user enables the timer while already in combat, show it immediately.
            if UnitAffectingCombat and UnitAffectingCombat("player") then
                if not combatStartTime then
                    combatStartTime = GetTime()
                end
                wasInCombat = true
                lastTimerText = ""
                MSUF_Gameplay_TickCombatTimer()
            end
        else
            -- Ensure state is hard-reset when turned off.
            wasInCombat = false
            combatStartTime = nil
            lastTimerText = ""
        end
    else
        -- Legacy fallback (should be rare): if UpdateManager isn't available, keep existing behavior.
        if not updater then
            updater = CreateFrame("Frame")
        end
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
            local g = EnsureGameplayDefaults()
            if roundFunc then value = roundFunc(value) end
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
perClassHint:SetText("Keeps one profile across alts (Monk/Pala/etc) without changing the spell each time.")
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
meleeSharedWarn:SetText("|cffff8800No melee range spell selected — Crosshair will not work.|r")
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

    local function _MSUF_Button(name, point, rel, relPoint, x, y, w, h, text, field)
        local b = CreateFrame("Button", name, content, "UIPanelButtonTemplate")
        b:SetSize(w or 60, h or 20)
        b:SetPoint(point, rel, relPoint, x or 0, y or 0)
        b:SetText(text or "")
        if field then panel[field] = b end
        return b
    end

    -- Combat Timer header + separator
    local combatSeparator = _MSUF_Sep(subText, -36)
    local combatHeader = _MSUF_Header(combatSeparator, "Combat Timer")

    -- In-combat timer checkbox
    local combatTimerCheck = _MSUF_Check("MSUF_Gameplay_CombatTimerCheck", "TOPLEFT", combatHeader, "BOTTOMLEFT", 0, -8, "Enable in-combat timer", "combatTimerCheck", "enableCombatTimer")

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

    -- "The First Dance" (Rogue) timer checkbox
    local firstDanceCheck = _MSUF_Check("MSUF_Gameplay_FirstDanceCheck", "TOPLEFT", classSpecHeader, "BOTTOMLEFT", 0, -8, "Rogue: Track 'The First Dance' (6s after leaving combat)", "firstDanceCheck", "enableFirstDanceTimer")

    -- Combat crosshair header + separator
    local crosshairSeparator = _MSUF_Sep(firstDanceCheck, -20)
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

    local crosshairRangeWarn = _MSUF_Label("GameFontNormalSmall", "TOPLEFT", crosshairRangeHint, "BOTTOMLEFT", 0, -2, "|cffff8800No melee range spell selected — Crosshair will not work.|r", "crosshairRangeWarnText")
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

        -- Combat Timer dependents
        local timerOn = g.enableCombatTimer and true or false
        _MSUF_SetSliderEnabled(self.combatFontSizeSlider, timerOn)
        _MSUF_SetCheckEnabled(self.lockCombatTimerCheck, timerOn)

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

    lastControl = cooldownIconsCheck


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

        "enableCombatCrosshair",
        "enableCombatCrosshairMeleeRangeColor",
        "crosshairThickness",
        "crosshairSize",

        "cooldownIcons",

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

            {"combatCrosshairCheck", "enableCombatCrosshair"},
            {"crosshairRangeColorCheck", "enableCombatCrosshairMeleeRangeColor"},

            {"cooldownIconsCheck", "cooldownIcons", true},
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
        }
        for i = 1, #sliders do
            local t = sliders[i]
            SetSlider(t[1], t[2], t[3])
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

        -- Grey out dependent controls when their parent toggle is off
        if self.MSUF_UpdateGameplayDisabledStates then
            self:MSUF_UpdateGameplayDisabledStates()
        end
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

    -- Beim Öffnen des Panels SavedVariables → UI syncen
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
