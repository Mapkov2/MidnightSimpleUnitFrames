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
local GetSpecialization    = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo

-- Per-spec helper: returns the current specialization ID (globally unique)
-- or nil if unavailable.  Used as key in nameplateMeleeSpellIDBySpec.
local function MSUF_GetPlayerSpecID()
    if not GetSpecialization then return nil end
    local specIndex = GetSpecialization()
    if not specIndex or specIndex <= 0 then return nil end
    if not GetSpecializationInfo then return nil end
    local specID = GetSpecializationInfo(specIndex)
    if not specID or specID <= 0 then return nil end
    return specID
end

-- Sub Rogue guard: Spec ID 261 = Subtlety Rogue
local _SUB_ROGUE_SPEC_ID = 261
local _isSubRogue = false

local function MSUF_IsSubRogue()
    if not UnitClass then return false end
    local _, cls = UnitClass("player")
    if cls ~= "ROGUE" then return false end
    return MSUF_GetPlayerSpecID() == _SUB_ROGUE_SPEC_ID
end

local function _UpdateSubRogueCache()
    _isSubRogue = MSUF_IsSubRogue()
end

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


local _MSUF_RoundInt = _G._MSUF_RoundInt
if not _MSUF_RoundInt then
    _MSUF_RoundInt = function(v)
        v = tonumber(v)
        if not v then
            return 0
        end
        if v >= 0 then
            return math.floor(v + 0.5)
        end
        return math.ceil(v - 0.5)
    end
    _G._MSUF_RoundInt = _MSUF_RoundInt
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
    -- When enabled, the combat timer frame never steals clicks (recommended).
    -- When disabled, the timer can be dragged normally while unlocked (no ALT needed).
    if g.combatTimerClickThrough == nil then
        g.combatTimerClickThrough = true
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

    -- Rogue "The First Dance" timer (6s after leaving combat)
    if g.enableFirstDanceTimer == nil then
        g.enableFirstDanceTimer = false
    end
    if g.firstDanceOffsetX == nil then g.firstDanceOffsetX = 0 end
    if g.firstDanceOffsetY == nil then g.firstDanceOffsetY = 80 end
    if g.lockFirstDance == nil then g.lockFirstDance = false end
    if g.firstDanceClickThrough == nil then g.firstDanceClickThrough = true end
    if g.firstDanceShowIcon == nil then g.firstDanceShowIcon = true end
    if g.firstDanceIconSize == nil or g.firstDanceIconSize <= 0 then g.firstDanceIconSize = 40 end
    if g.firstDanceIconSize < 16 then g.firstDanceIconSize = 16
    elseif g.firstDanceIconSize > 96 then g.firstDanceIconSize = 96 end
    if g.firstDanceShowReady == nil then g.firstDanceShowReady = true end

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
    -- Per-class / per-spec storage for the melee range spell
    if g.meleeSpellPerClass == nil then g.meleeSpellPerClass = false end
    if g.meleeSpellPerSpec == nil then g.meleeSpellPerSpec = false end
    if type(g.nameplateMeleeSpellIDByClass) ~= "table" then g.nameplateMeleeSpellIDByClass = {} end
    if type(g.nameplateMeleeSpellIDBySpec) ~= "table" then g.nameplateMeleeSpellIDBySpec = {} end
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
local firstDanceFrame
local firstDanceText
local firstDanceIcon
local firstDanceCooldown
local firstDanceCDText

local _FIRST_DANCE_ICON_ID = 236279

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
        -- Per-spec storage takes priority over per-class.
        -- Resolution order: per-spec -> per-class -> global fallback.
        if g.meleeSpellPerSpec and type(g.nameplateMeleeSpellIDBySpec) == "table" then
            local specID = MSUF_GetPlayerSpecID()
            if specID then
                local perSpec = tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0
                if perSpec > 0 then
                    spellID = perSpec
                end
            end
        end

        -- Per-class fallback (only if per-spec didn't resolve)
        if spellID <= 0 and g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
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
        if combatFrame and combatFrame.IsShown and combatFrame:IsShown() then
            combatFrame:Hide()
        end
        wasInCombat = false
        combatStartTime = nil
        return
    end

    -- UnitAffectingCombat is the most reliable signal for "combat started" timing.
    -- InCombatLockdown is a safe fallback.
    local inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) or (_G.MSUF_InCombat == true)

    if inCombat then
        if combatFrame and combatFrame.Show and (not combatFrame:IsShown()) then
            combatFrame:Show()
        end
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
        -- Out of combat: when locked, hide the entire timer (no preview).
        -- When unlocked, show a 0:00 preview so the user can position it.
        if gNow.lockCombatTimer then
            if combatFrame and combatFrame.IsShown and combatFrame:IsShown() then
                combatFrame:Hide()
            end
            if lastTimerText ~= "" then
                lastTimerText = ""
                combatTimerText:SetText("")
            end
        else
            if combatFrame and combatFrame.Show and (not combatFrame:IsShown()) then
                combatFrame:Show()
            end
            if lastTimerText ~= "0:00" then
                lastTimerText = "0:00"
                combatTimerText:SetText("0:00")
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
local firstDanceReady = false

local _TickFirstDance  -- forward declaration (defined after StartFirstDanceWindow)

-- Phase 7A: stop the FirstDance OnUpdate tick (event-driven start/stop)
local function _StopFirstDanceTick()
    firstDanceActive = false
    firstDanceEndTime = 0
    firstDanceLastText = nil
    if firstDanceFrame then firstDanceFrame:SetScript("OnUpdate", nil) end
    if firstDanceText then firstDanceText:SetText("") end
    if firstDanceCDText then firstDanceCDText:SetText("") end
    if firstDanceCooldown and firstDanceCooldown.SetCooldown then firstDanceCooldown:SetCooldown(0, 0) end
end

-- Hide the "ready" persistent indicator (called on Shadow Dance cast or feature disable)
local function _HideFirstDanceReady()
    firstDanceReady = false
    if firstDanceFrame then firstDanceFrame:Hide() end
    if firstDanceText then firstDanceText:SetText("") end
    if firstDanceCDText then firstDanceCDText:SetText("") end
    if firstDanceCooldown and firstDanceCooldown.SetCooldown then firstDanceCooldown:SetCooldown(0, 0) end
end

------------------------------------------------------
-- Shadow Dance listener: hide ready icon on cast (185313)
-- RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED","player") = zero dispatch cost for other units.
-- Only registered while firstDanceReady == true.
------------------------------------------------------
local _SHADOW_DANCE_SPELL_ID = 185313
local _fdShadowDanceFrame

local function _UnregisterShadowDanceWatch()
    if _fdShadowDanceFrame then
        _fdShadowDanceFrame:UnregisterAllEvents()
    end
end

local function _RegisterShadowDanceWatch()
    if not _isSubRogue then return end
    if not _fdShadowDanceFrame then
        _fdShadowDanceFrame = CreateFrame("Frame")
        _fdShadowDanceFrame:SetScript("OnEvent", function(_, _, _, _, spellID)
            if spellID == _SHADOW_DANCE_SPELL_ID then
                _UnregisterShadowDanceWatch()
                _HideFirstDanceReady()
                -- OOC Shadow Dance (e.g. supercharged combo points): restart 6s window
                if not UnitAffectingCombat("player") then
                    local gd = GetGameplayDBFast()
                    if gd and gd.enableFirstDanceTimer and ns._MSUF_StartFirstDanceWindow then
                        ns._MSUF_StartFirstDanceWindow()
                    end
                end
            end
        end)
    end
    _fdShadowDanceFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
end

-- Wrap _HideFirstDanceReady to also unregister the watcher
local _HideFirstDanceReady_Base = _HideFirstDanceReady
_HideFirstDanceReady = function()
    _UnregisterShadowDanceWatch()
    _HideFirstDanceReady_Base()
end

-- Make the combat enter/leave text click-through while it is actively displayed
-- so it never steals clicks / focus (e.g. targeting) while flashing on screen.
-- When cleared, mouse is restored based on the lock setting AND text visibility.
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
    -- Only allow mouse interaction when unlocked AND text is actually visible.
    -- Otherwise the invisible 220x60 frame at DIALOG strata steals clicks.
    if g and not g.lockCombatState and combatStateText and combatStateText:IsShown() then
        combatStateFrame:EnableMouse(true)
    else
        combatStateFrame:EnableMouse(false)
    end
end

------------------------------------------------------
-- First Dance: independent frame + clickthrough
------------------------------------------------------
local function _ApplyFirstDanceLockState()
    if not firstDanceFrame then return end
    local g = GetGameplayDBFast()
    if not g then return end
    if firstDanceFrame._msufDragging then
        firstDanceFrame:EnableMouse(true)
        return
    end
    if not g.enableFirstDanceTimer then
        firstDanceFrame:EnableMouse(false)
        return
    end
    if g.lockFirstDance then
        firstDanceFrame:EnableMouse(false)
        return
    end
    if g.firstDanceClickThrough ~= false then
        if IsAltKeyDown and IsAltKeyDown() then
            firstDanceFrame:EnableMouse(true)
        else
            firstDanceFrame:EnableMouse(false)
        end
        return
    end
    firstDanceFrame:EnableMouse(true)
end

local function EnsureFirstDanceFrame()
    if firstDanceFrame then return firstDanceFrame end
    local g = EnsureGameplayDefaults()

    firstDanceFrame = CreateFrame("Frame", "MSUF_FirstDanceFrame", UIParent)
    firstDanceFrame:SetSize(220, 60)
    firstDanceFrame:SetPoint("CENTER", UIParent, "CENTER", tonumber(g.firstDanceOffsetX) or 0, tonumber(g.firstDanceOffsetY) or 80)
    firstDanceFrame:SetFrameStrata("DIALOG")
    firstDanceFrame:SetClampedToScreen(true)
    firstDanceFrame:SetMovable(true)
    firstDanceFrame:RegisterForDrag("LeftButton")

    firstDanceFrame:SetScript("OnDragStart", function(self)
        local gd = EnsureGameplayDefaults()
        if gd.lockFirstDance then return end
        if gd.firstDanceClickThrough ~= false then
            if not (IsAltKeyDown and IsAltKeyDown()) then return end
        end
        self._msufDragging = true
        self:StartMoving()
    end)

    firstDanceFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._msufDragging = nil
        local db = EnsureGameplayDefaults()
        local x, y = self:GetCenter()
        if x and y then
            local ux, uy = UIParent:GetCenter()
            if ux and uy then
                db.firstDanceOffsetX = _MSUF_RoundInt(x - ux)
                db.firstDanceOffsetY = _MSUF_RoundInt(y - uy)
            end
        end
        local p = _G and _G.MSUF_GameplayPanel
        if p and p.MSUF_SyncFirstDanceOffsetSliders then
            p:MSUF_SyncFirstDanceOffsetSliders()
        end
        _ApplyFirstDanceLockState()
    end)

    -- Text mode elements
    firstDanceText = firstDanceFrame:CreateFontString(nil, "OVERLAY")
    firstDanceText:SetPoint("CENTER")

    -- Icon mode elements
    local iconSz = g.firstDanceIconSize or 40
    firstDanceIcon = firstDanceFrame:CreateTexture(nil, "ARTWORK")
    firstDanceIcon:SetTexture(_FIRST_DANCE_ICON_ID)
    firstDanceIcon:SetSize(iconSz, iconSz)
    firstDanceIcon:SetPoint("CENTER")

    firstDanceCooldown = CreateFrame("Cooldown", "MSUF_FirstDanceCooldown", firstDanceFrame, "CooldownFrameTemplate")
    firstDanceCooldown:SetAllPoints(firstDanceIcon)
    firstDanceCooldown:SetDrawEdge(true)
    firstDanceCooldown:SetDrawSwipe(true)
    firstDanceCooldown:SetReverse(true)
    firstDanceCooldown:SetHideCountdownNumbers(true)

    firstDanceCDText = firstDanceCooldown:CreateFontString(nil, "OVERLAY")
    firstDanceCDText:SetPoint("CENTER", firstDanceCooldown, "CENTER", 0, 0)

    _ApplyFirstDanceLockState()

    -- Modifier listener for ALT-to-drag (same pattern as combat timer)
    if not ns._MSUF_FirstDanceModifierFrame then
        local mf = CreateFrame("Frame")
        ns._MSUF_FirstDanceModifierFrame = mf
        mf:RegisterEvent("MODIFIER_STATE_CHANGED")
        mf:SetScript("OnEvent", function()
            if not firstDanceFrame then return end
            if firstDanceFrame._msufDragging then
                firstDanceFrame:EnableMouse(true)
                return
            end
            local gd = GetGameplayDBFast()
            if not gd or not gd.enableFirstDanceTimer or gd.lockFirstDance then
                if firstDanceFrame then firstDanceFrame:EnableMouse(false) end
                return
            end
            if gd.firstDanceClickThrough == false then
                firstDanceFrame:EnableMouse(true)
                return
            end
            if IsAltKeyDown and IsAltKeyDown() then
                firstDanceFrame:EnableMouse(true)
            else
                firstDanceFrame:EnableMouse(false)
            end
        end)
    end

    return firstDanceFrame
end

-- Switch between icon and text display; also applies icon size
local function _ApplyFirstDanceDisplayMode()
    if not firstDanceFrame then return end
    local g = GetGameplayDBFast()
    if not g then return end
    local iconMode = (g.firstDanceShowIcon ~= false)
    local iconSz = g.firstDanceIconSize or 40

    if iconMode then
        if firstDanceText then firstDanceText:Hide() end
        if firstDanceIcon then
            firstDanceIcon:SetSize(iconSz, iconSz)
            firstDanceIcon:Show()
        end
        if firstDanceCooldown then firstDanceCooldown:Show() end
        if firstDanceCDText then firstDanceCDText:Show() end
        firstDanceFrame:SetSize(iconSz + 4, iconSz + 4)
        -- Register with Masque if available (icon mode only)
        if ns.MSUF_FirstDance_ApplyMasque then ns.MSUF_FirstDance_ApplyMasque() end
    else
        if firstDanceIcon then firstDanceIcon:Hide() end
        if firstDanceCooldown then firstDanceCooldown:Hide() end
        if firstDanceCDText then firstDanceCDText:Hide() end
        if firstDanceText then firstDanceText:Show() end
        firstDanceFrame:SetSize(220, 60)
    end
end

------------------------------------------------------
-- First Dance: Masque integration (optional, lightweight)
-- Separate group "First Dance" under MSUF; uses A2's masqueEnabled flag.
-- Only Icon + Cooldown passed — never Count (MSUF manages CDText).
------------------------------------------------------
do
    local _fdMasqueGroup
    local _fdMasqueRegistered = false

    local function _FD_IsMasqueEnabled()
        local a2db = MSUF_DB and MSUF_DB.auras2
        local shared = a2db and a2db.shared
        return shared and shared.masqueEnabled == true
    end

    local function _FD_EnsureMasqueGroup()
        if _fdMasqueGroup then return _fdMasqueGroup end
        if not LibStub then return nil end
        local ok, lib = pcall(LibStub, "Masque", true)
        if not ok or not lib then return nil end
        local ok2, grp = pcall(lib.Group, lib, "Midnight Simple Unit Frames", "First Dance")
        if not ok2 or not grp then return nil end
        _fdMasqueGroup = grp
        return grp
    end

    function ns.MSUF_FirstDance_ApplyMasque()
        if not firstDanceFrame then return end

        if not _FD_IsMasqueEnabled() then
            if _fdMasqueRegistered and _fdMasqueGroup then
                pcall(_fdMasqueGroup.RemoveButton, _fdMasqueGroup, firstDanceFrame)
                _fdMasqueRegistered = false
            end
            return
        end

        local grp = _FD_EnsureMasqueGroup()
        if not grp then return end

        if _fdMasqueRegistered then return end

        local regions = {
            Icon     = firstDanceIcon,
            Cooldown = firstDanceCooldown,
        }
        local ok = pcall(grp.AddButton, grp, firstDanceFrame, regions)
        if ok then
            _fdMasqueRegistered = true
            -- Single ReSkin after registration
            if grp.ReSkin then pcall(grp.ReSkin, grp) end
            -- Keep CDText above Masque layers
            if firstDanceCooldown and firstDanceCDText then
                local base = firstDanceCooldown.GetFrameLevel and firstDanceCooldown:GetFrameLevel() or 0
                local overlay = CreateFrame("Frame", nil, firstDanceCooldown)
                overlay:SetAllPoints()
                overlay:SetFrameLevel(base + 5)
                firstDanceCDText:SetParent(overlay)
                firstDanceCDText:ClearAllPoints()
                firstDanceCDText:SetPoint("CENTER")
            end
        end
    end
end

local function _ApplyFirstDanceFont()
    local path, flags, r, gCol, bCol, size, useShadow = GetGameplayFontSettings("state")
    local g = GetGameplayDBFast()
    local _er, _eg, _eb, lr, lg, lb = MSUF_GetCombatStateColors(g)

    if firstDanceText then
        firstDanceText:SetFont(path or "Fonts/FRIZQT__.TTF", (size or 24), flags or "OUTLINE")
        firstDanceText:SetTextColor(lr, lg, lb, 1)
        if useShadow then
            firstDanceText:SetShadowOffset(1, -1)
            firstDanceText:SetShadowColor(0, 0, 0, 1)
        else
            firstDanceText:SetShadowOffset(0, 0)
        end
    end

    if firstDanceCDText then
        local iconSz = (g and g.firstDanceIconSize) or 40
        local cdFontSz = math_max(10, math.floor(iconSz * 0.45 + 0.5))
        firstDanceCDText:SetFont(path or "Fonts/FRIZQT__.TTF", cdFontSz, "OUTLINE")
        firstDanceCDText:SetTextColor(1, 1, 1, 1)
        if useShadow then
            firstDanceCDText:SetShadowOffset(1, -1)
            firstDanceCDText:SetShadowColor(0, 0, 0, 1)
        else
            firstDanceCDText:SetShadowOffset(0, 0)
        end
    end
end

local function ApplyFontToCounter()
    -- If nothing exists yet, nothing to do
    if not combatTimerText and not combatStateText and not firstDanceText then
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

    -- First Dance text font
    _ApplyFirstDanceFont()
end

local EnsureCombatStateText

------------------------------------------------------
-- "The First Dance" helper
------------------------------------------------------
local function StartFirstDanceWindow()
    if not _isSubRogue then return end
    local g = GetGameplayDBFast()

    -- Feature off = make sure state is hard-reset and updater is off
    if not g or not g.enableFirstDanceTimer then
        _StopFirstDanceTick()
        _HideFirstDanceReady()
        return
    end

    if not firstDanceFrame then
        EnsureFirstDanceFrame()
    end
    if not firstDanceFrame then return end

    firstDanceEndTime = GetTime() + FIRST_DANCE_WINDOW
    firstDanceActive = true
    firstDanceReady = false
    firstDanceLastText = nil

    _ApplyFirstDanceFont()
    _ApplyFirstDanceDisplayMode()

    -- Icon mode: kick the cooldown swipe
    if g.firstDanceShowIcon ~= false and firstDanceCooldown then
        firstDanceCooldown:SetCooldown(GetTime(), FIRST_DANCE_WINDOW)
    end

    firstDanceFrame:Show()

    -- Start the tick for this animation window
    firstDanceFrame:SetScript("OnUpdate", function(self, elapsed)
        _TickFirstDance()
    end)

end

-- Export for deferred callback access (Shadow Dance OOC restart)
ns._MSUF_StartFirstDanceWindow = StartFirstDanceWindow

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
    if not g or (not g.enableCombatStateText and not (g.enableFirstDanceTimer and _isSubRogue)) then
        if combatStateText then
            combatStateText:SetText("")
            combatStateText:Hide()
        end
        MSUF_CombatState_SetClickThrough(false)
        _StopFirstDanceTick()
        _HideFirstDanceReady()
        return
    end

    local wantState = (g.enableCombatStateText == true)
    local wantDance = (g.enableFirstDanceTimer == true) and _isSubRogue

    local duration = g.combatStateDuration or 1.5
    if duration < 0.1 then
        duration = 0.1
    end

    if event == "PLAYER_REGEN_DISABLED" then
        -- Enter combat: stop countdown; ready icon persists until Shadow Dance
        local wasActive = firstDanceActive
        _StopFirstDanceTick()
        if wasActive and not firstDanceReady then
            -- Countdown was interrupted (6s not complete) → hide
            if firstDanceFrame then firstDanceFrame:Hide() end
        end
        -- If firstDanceReady, the Shadow Dance watcher handles hide

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
        -- Leave combat: always start 6s First Dance countdown + show "-Combat" if wanted
        _StopFirstDanceTick()

        if wantDance and not firstDanceReady then
            StartFirstDanceWindow()
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
    if not gFD or not gFD.enableFirstDanceTimer then
        _StopFirstDanceTick()
        _HideFirstDanceReady()
        return
    end

    if not firstDanceFrame then
        EnsureFirstDanceFrame()
    end
    if not firstDanceFrame then return end

    local now = GetTime()
    local remaining = firstDanceEndTime - now
    if remaining <= 0 then
        _StopFirstDanceTick()

        -- Show persistent "ready" indicator if enabled
        if gFD.firstDanceShowReady then
            firstDanceReady = true
            _RegisterShadowDanceWatch()
            local iconMode = (gFD.firstDanceShowIcon ~= false)
            if iconMode then
                if firstDanceCDText then firstDanceCDText:SetText("") end
                if firstDanceCooldown and firstDanceCooldown.SetCooldown then firstDanceCooldown:SetCooldown(0, 0) end
                if firstDanceIcon then firstDanceIcon:SetDesaturated(false) end
            else
                if firstDanceText then firstDanceText:SetText("First Dance!") end
            end
            -- Frame stays visible; hidden on Shadow Dance cast
        else
            if firstDanceFrame then firstDanceFrame:Hide() end
        end
        return
    end

    local iconMode = (gFD.firstDanceShowIcon ~= false)
    if iconMode then
        -- Icon mode: CD text shows remaining, swipe runs natively
        local text = string_format("%.1f", remaining)
        if text ~= firstDanceLastText then
            firstDanceLastText = text
            if firstDanceCDText then firstDanceCDText:SetText(text) end
        end
    else
        -- Text mode
        local text = string_format("First Dance: %.1f", remaining)
        if text ~= firstDanceLastText then
            firstDanceLastText = text
            if firstDanceText then firstDanceText:SetText(text) end
        end
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

                local inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) or (_G.MSUF_InCombat == true)

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
        -- Combat Timer mouse behavior:
        -- • While dragging: keep mouse enabled so OnDragStop always fires (prevents "stuck to mouse").
        -- • Locked: always click-through (never steal clicks / never invisible clickbox).
        -- • Unlocked: either click-through with ALT-to-drag, or always-interactive when click-through is disabled.
        if combatFrame._msufDragging then
            combatFrame:EnableMouse(true)
        elseif not g.enableCombatTimer then
            combatFrame:EnableMouse(false)
        elseif g.lockCombatTimer then
            combatFrame:EnableMouse(false)
        else
            local clickThrough = (g.combatTimerClickThrough ~= false)
            if clickThrough then
                if IsAltKeyDown and IsAltKeyDown() then
                    combatFrame:EnableMouse(true)
                else
                    combatFrame:EnableMouse(false)
                end
            else
                combatFrame:EnableMouse(true)
            end
        end
    end

    if combatStateFrame then
        if combatStateFrame._msufClickThroughActive then
            combatStateFrame:EnableMouse(false)
        elseif g.lockCombatState then
            combatStateFrame:EnableMouse(false)
        elseif combatStateText and combatStateText:IsShown() then
            combatStateFrame:EnableMouse(true)
        else
            combatStateFrame:EnableMouse(false)
        end
    end

    _ApplyFirstDanceLockState()
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
    if f then
        -- Always return the chosen frame if it exists.
        -- The anchor must work even if the frame is currently hidden or has no center yet.
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

        -- Safety: if click-through is enabled, dragging is only allowed while ALT is held.
        -- (Prevents accidental drags when the frame is temporarily interactive.)
        if gd.combatTimerClickThrough ~= false then
            if not (IsAltKeyDown and IsAltKeyDown()) then
                return
            end
        end

        self._msufDragging = true
        self:StartMoving()
    end)

    combatFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._msufDragging = nil

        -- Use the same proven "combat enter/leave" drag-save logic:
        -- store offsets from the CURRENT anchor's center (or UIParent fallback).
        local db = EnsureGameplayDefaults()
        local anchor = _MSUF_GetCombatTimerAnchorFrame(db)

        local x, y = self:GetCenter()
        if x and y then
            local ax, ay = UIParent:GetCenter()
            if anchor and anchor.GetCenter then
                local tx, ty = anchor:GetCenter()
                if tx and ty then
                    ax, ay = tx, ty
                end
            end
            if ax and ay then
                db.combatOffsetX = _MSUF_RoundInt(x - ax)
                db.combatOffsetY = _MSUF_RoundInt(y - ay)
            end
        end

        -- Live-sync offset sliders in the Gameplay panel (if open).
        local p = _G and _G.MSUF_GameplayPanel
        if p and p.MSUF_SyncCombatTimerOffsetSliders then
            p:MSUF_SyncCombatTimerOffsetSliders()
        end

        -- Re-apply click-through / ALT-to-drag state after the drag ends.
        ApplyLockState()
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

            -- Never toggle mouse while dragging; otherwise OnDragStop can fail to fire
            -- and the frame may appear to "stick" to the cursor.
            if combatFrame._msufDragging then
                combatFrame:EnableMouse(true)
                return
            end

            local gd = GetGameplayDBFast()
            if not gd or not gd.enableCombatTimer or gd.lockCombatTimer then
                if combatFrame then combatFrame:EnableMouse(false) end
                return
            end

            -- If click-through is disabled, keep it interactive while unlocked.
            if gd.combatTimerClickThrough == false then
                combatFrame:EnableMouse(true)
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
    if _G.MSUF_InCombat then
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
    _UpdateSubRogueCache()
    local wantState = (g.enableCombatStateText == true)
    -- First Dance nur für Sub Rogue
    local wantDance = (g.enableFirstDanceTimer == true) and _isSubRogue

    -- Combat State Text (enter/leave)
    if wantState then
        EnsureCombatStateText()
        MSUF_CombatState_SetClickThrough(false)

        -- Phase 7B: combat state events via EventBus
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_STATE", MSUF_CombatState_OnEvent)
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_STATE", MSUF_CombatState_OnEvent)
        end

        -- Preview while unlocked
        if not g.lockCombatState and combatStateText then
            local enterText = g.combatStateEnterText
            if type(enterText) ~= "string" or enterText == "" then
                enterText = "+Combat"
            end
            local er, eg, eb = MSUF_GetCombatStateColors(g)
            combatStateText._msufLastState = "enter"
            combatStateText:SetTextColor(er, eg, eb, 1)
            combatStateText:SetText(enterText)
            combatStateText:Show()
        elseif combatStateText then
            combatStateText:SetText("")
            combatStateText:Hide()
        end
    else
        if combatStateText then
            combatStateText:SetText("")
            combatStateText:Hide()
        end
        MSUF_CombatState_SetClickThrough(false)
    end

    -- First Dance (own frame, independent from combat state text)
    if wantDance then
        EnsureFirstDanceFrame()
        _ApplyFirstDanceFont()
        _ApplyFirstDanceDisplayMode()

        -- EventBus: First Dance trigger on regen events (shared keys with combat state)
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_STATE", MSUF_CombatState_OnEvent)
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_STATE", MSUF_CombatState_OnEvent)
        end

        -- Preview while unlocked; keep ready indicator when locked + ready
        if not g.lockFirstDance and firstDanceFrame and not firstDanceActive and not firstDanceReady then
            -- Unlocked, not counting, not ready → show preview
            local iconMode = (g.firstDanceShowIcon ~= false)
            if iconMode then
                if firstDanceCDText then firstDanceCDText:SetText("6.0") end
            else
                if firstDanceText then firstDanceText:SetText("First Dance: 6.0") end
            end
            firstDanceFrame:Show()
        elseif firstDanceFrame and not firstDanceActive and not firstDanceReady then
            -- Locked, not counting, not ready → hide
            if firstDanceText then firstDanceText:SetText("") end
            if firstDanceCDText then firstDanceCDText:SetText("") end
            firstDanceFrame:Hide()
        end
        -- If firstDanceActive or firstDanceReady, leave frame as-is (tick/ready manages it)
        _ApplyFirstDanceLockState()
    else
        _StopFirstDanceTick()
        _HideFirstDanceReady()
    end

    -- Unregister EventBus if both features off
    if not wantState and not wantDance then
        if type(MSUF_EventBus_Unregister) == "function" then
            MSUF_EventBus_Unregister("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_STATE")
            MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_STATE")
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
            local inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) or (_G.MSUF_InCombat == true)
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
-- _MSUF_RoundInt: use module-level local (defined at top of file).
------------------------------------------------------

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





-- Feature tables (single-file modules) for readability and safer future refactors
local GameplayFeatures = {
    CombatTimer     = {},
    CombatStateText = {},
    CombatCrosshair = {},
    PlayerTotems    = {},
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
local GameplayFeatureOrder = {"CombatTimer", "CombatStateText", "CombatCrosshair", "PlayerTotems"}

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

-- Spec-Wechsel: Sub-Rogue-Features sofort aktivieren/deaktivieren
do
    local _specChangeFrame = CreateFrame("Frame")
    _specChangeFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    _specChangeFrame:RegisterEvent("PLAYER_LOGIN")
    _specChangeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _specChangeFrame:SetScript("OnEvent", function()
        _UpdateSubRogueCache()
        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
    end)
end

------------------------------------------------------
-- ns: runtime exports for MSUF_Options_Gameplay.lua
------------------------------------------------------
do
    ns.MSUF_EnsureGameplayDefaults            = EnsureGameplayDefaults
    ns.MSUF_GetCombatTimerFrame               = function() return combatFrame end
    ns.MSUF_Gameplay_ApplyFontToCounter       = function() ApplyFontToCounter() end
    ns.MSUF_Gameplay_ApplyLockState           = function() ApplyLockState() end
    ns.MSUF_Gameplay_ApplyCombatTimerAnchorFn = function(g) MSUF_Gameplay_ApplyCombatTimerAnchor(g) end
    ns.MSUF_Gameplay_TickCombatTimer          = function() MSUF_Gameplay_TickCombatTimer() end
    ns.MSUF_GetCombatTimerAnchorFrame         = function(g) return _MSUF_GetCombatTimerAnchorFrame(g) end
    ns.MSUF_SetEnabledMeleeRangeCheck         = function(id) MSUF_SetEnabledMeleeRangeCheck(id) end
    ns.MSUF_BuildMeleeSpellCache              = function() MSUF_BuildMeleeSpellCache() end
    ns.MSUF_GetMeleeSpellCache                = function() return MSUF_MeleeSpellCache end
    ns.MSUF_GetPlayerSpecID                   = MSUF_GetPlayerSpecID
    ns.MSUF_GetFirstDanceFrame                = function() return firstDanceFrame end
    ns.MSUF_ApplyFirstDanceLockState          = function() _ApplyFirstDanceLockState() end
    ns.MSUF_ApplyFirstDanceDisplayMode        = function() _ApplyFirstDanceDisplayMode() end
end

-- Options panel registration: see MSUF_Options_Gameplay.lua
-- These stubs ensure backward compat if called before the options file loads.
function ns.MSUF_RegisterGameplayOptions_Full(parentCategory)
    -- Options UI is built in MSUF_Options_Gameplay.lua (lazy-loaded).
    -- This stub is a no-op safety net; the real implementation overrides it.
end

function ns.MSUF_RegisterGameplayOptions(parentCategory)
    -- Overridden by MSUF_Options_Gameplay.lua on load.
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

        _UpdateSubRogueCache()

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

-- ============================================================================
-- Phase 4: Module Registration
-- Gameplay registers into the unified module lifecycle so that:
--   - Profile switches broadcast RefreshSettings → all features re-apply
--   - Debug toggle can disable/re-enable all gameplay features at runtime
--   - Shutdown cleans up tickers + EventBus registrations on profile switch
-- Internal feature toggles (combat timer, crosshair, etc.) remain unchanged.
-- ============================================================================
do
    local reg = (ns and ns.MSUF_RegisterModule) or _G.MSUF_RegisterModule
    if type(reg) == "function" then
        reg("Gameplay", {
            order = 50,
            IsEnabled = function() return true end,
            Init = function()
                if type(EnsureGameplayDefaults) == "function" then
                    EnsureGameplayDefaults()
                end
            end,
            Enable = function()
                if ns and ns.MSUF_RequestGameplayApply then
                    ns.MSUF_RequestGameplayApply()
                end
            end,
            Disable = function()
                -- Stop combat timer ticker
                if ns._MSUF_CombatTimerTicker then
                    ns._MSUF_CombatTimerTicker:Cancel()
                    ns._MSUF_CombatTimerTicker = nil
                end
                -- Unregister EventBus keys (idempotent)
                local unreg = _G.MSUF_EventBus_Unregister
                if type(unreg) == "function" then
                    unreg("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_TIMER")
                    unreg("PLAYER_REGEN_ENABLED",  "MSUF_COMBAT_TIMER")
                    unreg("PLAYER_ENTERING_WORLD", "MSUF_COMBAT_TIMER")
                    unreg("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_STATE")
                    unreg("PLAYER_REGEN_ENABLED",  "MSUF_COMBAT_STATE")
                end
            end,
            RefreshSettings = function(_, source)
                if ns and ns.MSUF_RequestGameplayApply then
                    ns.MSUF_RequestGameplayApply()
                end
            end,
            Shutdown = function(_, reason)
                -- Stop all tickers
                if ns._MSUF_CombatTimerTicker then
                    ns._MSUF_CombatTimerTicker:Cancel()
                    ns._MSUF_CombatTimerTicker = nil
                end
                -- Unregister all EventBus keys
                local unreg = _G.MSUF_EventBus_Unregister
                if type(unreg) == "function" then
                    unreg("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_TIMER")
                    unreg("PLAYER_REGEN_ENABLED",  "MSUF_COMBAT_TIMER")
                    unreg("PLAYER_ENTERING_WORLD", "MSUF_COMBAT_TIMER")
                    unreg("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_STATE")
                    unreg("PLAYER_REGEN_ENABLED",  "MSUF_COMBAT_STATE")
                end
            end,
        })
    end
end
