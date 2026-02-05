--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua"); -- MidnightSimpleUnitFrames_Gameplay.lua
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
------------------------------------------------------
-- Small math helpers
------------------------------------------------------
local _MSUF_Clamp = _G._MSUF_Clamp
if not _MSUF_Clamp then
    _MSUF_Clamp = function(v, mn, mx) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:32:18");
        v = tonumber(v)
        if not v then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:32:18"); return mn
        end
        if v < mn then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:32:18"); return mn
        end
        if v > mx then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:32:18"); return mx
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:32:18"); return v
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

    function ns.MSUF_RequestGameplayApply() Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_RequestGameplayApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:58:4");
        if _applyPending then
            Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_RequestGameplayApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:58:4"); return
        end
        _applyPending = true

        if C_Timer_After then
            C_Timer_After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:65:29");
                _applyPending = false
                if ns and ns.MSUF_ApplyGameplayVisuals then
                    ns.MSUF_ApplyGameplayVisuals()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:65:29"); end)
        else
            _applyPending = false
            if ns and ns.MSUF_ApplyGameplayVisuals then
                ns.MSUF_ApplyGameplayVisuals()
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_RequestGameplayApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:58:4"); end
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
local function MSUF_GetUpdateManager() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetUpdateManager file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:102:6");
    return Perfy_Trace_Passthrough("Leave", "MSUF_GetUpdateManager file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:102:6", _G.MSUF_UpdateManager or (ns and ns.MSUF_UpdateManager))
end

------------------------------------------------------
-- SavedVars helper (own sub-table under MSUF_DB)
------------------------------------------------------
local gameplayDBCache

local function EnsureGameplayDefaults() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureGameplayDefaults file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:111:6");
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

    -- One-time tip popup flag
    if g.shownGameplayColorsTip == nil then
        g.shownGameplayColorsTip = false
    end

    gameplayDBCache = g
    Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureGameplayDefaults file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:111:6"); return g
end

-- Hotpath helper: avoid calling EnsureGameplayDefaults() every tick.
-- The gameplay DB table is stable; this cache is refreshed whenever EnsureGameplayDefaults() runs.
local function GetGameplayDBFast() Perfy_Trace(Perfy_GetTime(), "Enter", "GetGameplayDBFast file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:307:6");
    if type(gameplayDBCache) == "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "GetGameplayDBFast file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:307:6"); return gameplayDBCache
    end
    return Perfy_Trace_Passthrough("Leave", "GetGameplayDBFast file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:307:6", EnsureGameplayDefaults())
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

    local function _Run() Perfy_Trace(Perfy_GetTime(), "Enter", "_Run file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:327:10");
        _pending = false
        EnsureGameplayDefaults()

        local fn = _G and _G.MSUF_ApplyCooldownIconMode
        if type(fn) == "function" then
            -- Optional module: keep errors visible during dev; but don't hard-break login.
            pcall(fn)
            Perfy_Trace(Perfy_GetTime(), "Leave", "_Run file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:327:10"); return
        end

        -- Fallback for older builds: just let the icon module decide whether to keep OnUpdate alive.
        fn = _G and _G.MSUF_CDIcons_UpdateOnUpdateState
        if type(fn) == "function" then
            pcall(fn)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_Run file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:327:10"); end

    local function RequestSync() Perfy_Trace(Perfy_GetTime(), "Enter", "RequestSync file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:345:10");
        if _pending then Perfy_Trace(Perfy_GetTime(), "Leave", "RequestSync file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:345:10"); return end
        _pending = true
        if C_Timer_After then
            C_Timer_After(0, _Run)
        else
            _Run()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "RequestSync file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:345:10"); end

    -- Expose for Options panel handlers (keeps all call sites consistent).
    if ns then
        ns.MSUF_RequestCooldownIconsSync = RequestSync
    end

    local function TryHook() Perfy_Trace(Perfy_GetTime(), "Enter", "TryHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:360:10");
        if _hooked then Perfy_Trace(Perfy_GetTime(), "Leave", "TryHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:360:10"); return end
        local ecv = _G and _G["EssentialCooldownViewer"]
        if not ecv or not ecv.HookScript then Perfy_Trace(Perfy_GetTime(), "Leave", "TryHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:360:10"); return end
        _hooked = true

        ecv:HookScript("OnShow", RequestSync)
        ecv:HookScript("OnHide", RequestSync)
        ecv:HookScript("OnSizeChanged", RequestSync)

        RequestSync()
    Perfy_Trace(Perfy_GetTime(), "Leave", "TryHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:360:10"); end

    local function ScheduleHookAttempts() Perfy_Trace(Perfy_GetTime(), "Enter", "ScheduleHookAttempts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:373:10");
        local tries = 0
        local function attempt() Perfy_Trace(Perfy_GetTime(), "Enter", "attempt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:375:14");
            tries = tries + 1
            TryHook()
            if (not _hooked) and tries < 10 and C_Timer_After then
                C_Timer_After(1, attempt)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "attempt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:375:14"); end
        if C_Timer_After then
            C_Timer_After(1, attempt)
        else
            attempt()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ScheduleHookAttempts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:373:10"); end

    RequestSync()
    ScheduleHookAttempts()
end


------------------------------------------------------
-- One-time tip popup: gameplay colors live in Colors → Gameplay
------------------------------------------------------
do
    local POPUP_KEY = "MSUF_GAMEPLAY_COLORS_TIP"

    local function EnsureDialog() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:400:10");
        if not _G.StaticPopupDialogs then
            Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:400:10"); return false
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:400:10"); return true
    end

    function ns.MSUF_MaybeShowGameplayColorsTip() Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_MaybeShowGameplayColorsTip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:418:4");
        local g = EnsureGameplayDefaults()
        if g and g.shownGameplayColorsTip then
            Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_MaybeShowGameplayColorsTip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:418:4"); return
        end
        if EnsureDialog() and _G.StaticPopup_Show then
            -- Mark as shown before showing so we never spam, even if the dialog is dismissed instantly.
            if g then
                g.shownGameplayColorsTip = true
            end
            _G.StaticPopup_Show(POPUP_KEY)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_MaybeShowGameplayColorsTip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:418:4"); end
end


------------------------------------------------------
-- Font helper: reuse global MSUF text style
------------------------------------------------------
local function GetGameplayFontSettings(kind) Perfy_Trace(Perfy_GetTime(), "Enter", "GetGameplayFontSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:437:6");
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

    Perfy_Trace(Perfy_GetTime(), "Leave", "GetGameplayFontSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:437:6"); return fontPath, flags, fr, fg, fb, effSize, useShadow
end



------------------------------------------------------
-- Combat state text colors (Enter/Leave)
------------------------------------------------------
local function _MSUF_NormalizeRGB(tbl, dr, dg, db) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_NormalizeRGB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:506:6");
    if type(tbl) == "table" then
        local r = tonumber(tbl[1])
        local g = tonumber(tbl[2])
        local b = tonumber(tbl[3])
        if r and g and b then
            if r < 0 then r = 0 elseif r > 1 then r = 1 end
            if g < 0 then g = 0 elseif g > 1 then g = 1 end
            if b < 0 then b = 0 elseif b > 1 then b = 1 end
            Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_NormalizeRGB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:506:6"); return r, g, b
        end
    end
    return Perfy_Trace_Passthrough("Leave", "_MSUF_NormalizeRGB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:506:6", dr or 1, dg or 1, db or 1)
end

local function MSUF_GetCombatStateColors(g) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetCombatStateColors file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:521:6");
    -- Defaults match the legacy hardcoded values.
    local er, eg, eb = _MSUF_NormalizeRGB(g and g.combatStateEnterColor, 1, 1, 1)
    local lr, lg, lb = _MSUF_NormalizeRGB(g and g.combatStateLeaveColor, 0.7, 0.7, 0.7)

    if g and g.combatStateColorSync then
        lr, lg, lb = er, eg, eb
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetCombatStateColors file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:521:6"); return er, eg, eb, lr, lg, lb
end

local function MSUF_ApplyCombatStateDynamicColor() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyCombatStateDynamicColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:532:6");
    if not combatStateText and EnsureCombatStateText then
        EnsureCombatStateText()
    end

    if not combatStateText then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyCombatStateDynamicColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:532:6"); return
    end
    local g = GetGameplayDBFast()
    local er, eg, eb, lr, lg, lb = MSUF_GetCombatStateColors(g)

    local st = combatStateText._msufLastState
    if st == "leave" or st == "dance" then
        combatStateText:SetTextColor(lr, lg, lb, 1)
    else
        combatStateText:SetTextColor(er, eg, eb, 1)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyCombatStateDynamicColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:532:6"); end

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
local function MSUF_ResolveCrosshairRangeSpellIDFromGameplay(g) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ResolveCrosshairRangeSpellIDFromGameplay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:570:6");
    if type(g) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResolveCrosshairRangeSpellIDFromGameplay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:570:6"); return 0 end

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

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResolveCrosshairRangeSpellIDFromGameplay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:570:6"); return spellID
end

-- Cache crosshair runtime flags from gameplay DB so hotpaths don't repeatedly look up DB keys.
local function MSUF_CrosshairSyncRangeCacheFromGameplay(g) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CrosshairSyncRangeCacheFromGameplay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:605:6");
    if not combatCrosshairFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CrosshairSyncRangeCacheFromGameplay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:605:6"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CrosshairSyncRangeCacheFromGameplay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:605:6"); end



-- In-combat timer state
local combatStartTime = nil
local wasInCombat = false
local lastTimerText = ""

-- Shared combat timer tick (used by UpdateManager + immediate event refresh)
local function MSUF_Gameplay_TickCombatTimer() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Gameplay_TickCombatTimer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:638:6");
    if not combatTimerText then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Gameplay_TickCombatTimer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:638:6"); return
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Gameplay_TickCombatTimer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:638:6"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Gameplay_TickCombatTimer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:638:6"); end

-- Rogue "The First Dance" 6s window (out-of-combat)
local FIRST_DANCE_WINDOW = 6
local firstDanceActive = false
local firstDanceEndTime = 0
local firstDanceLastText = nil


-- Make the combat enter/leave text click-through while it is actively displayed
-- so it never steals clicks / focus (e.g. targeting) while flashing on screen.
-- When cleared, mouse is restored based on the lock setting.
local function MSUF_CombatState_SetClickThrough(active) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CombatState_SetClickThrough file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:706:6");
    if not combatStateFrame then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CombatState_SetClickThrough file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:706:6"); return
    end

    if active then
        combatStateFrame._msufClickThroughActive = true
        combatStateFrame:EnableMouse(false)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CombatState_SetClickThrough file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:706:6"); return
    end

    combatStateFrame._msufClickThroughActive = nil
    local g = GetGameplayDBFast()
    if g and g.lockCombatState then
        combatStateFrame:EnableMouse(false)
    else
        combatStateFrame:EnableMouse(true)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CombatState_SetClickThrough file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:706:6"); end


local function ApplyFontToCounter() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyFontToCounter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:727:6");
    -- If nothing exists yet, nothing to do
    if not combatTimerText and not combatStateText then
        Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyFontToCounter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:727:6"); return
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

Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyFontToCounter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:727:6"); end

local EnsureCombatStateText

------------------------------------------------------
-- "The First Dance" helper
------------------------------------------------------
local function StartFirstDanceWindow() Perfy_Trace(Perfy_GetTime(), "Enter", "StartFirstDanceWindow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:769:6");
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "StartFirstDanceWindow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:769:6"); return
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "StartFirstDanceWindow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:769:6"); return
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

    -- Ensure the First Dance tick task exists even if this triggers before a full Apply() pass.
    if EnsureFirstDanceTaskRegistered then
        EnsureFirstDanceTaskRegistered()
    end

    local umFD = MSUF_GetUpdateManager()
    if umFD and umFD.SetEnabled then
        umFD:SetEnabled("MSUF_GAMEPLAY_FIRSTDANCE", true)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "StartFirstDanceWindow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:769:6"); end

------------------------------------------------------
-- Combat state text (enter/leave combat)
------------------------------------------------------
EnsureCombatStateText = function() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureCombatStateText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:833:24");
    if combatStateText then
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureCombatStateText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:833:24"); return
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

        combatStateFrame:SetScript("OnDragStart", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:849:50");
            local gd = EnsureGameplayDefaults()
            if gd.lockCombatState then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:849:50"); return
            end
            self:StartMoving()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:849:50"); end)

        combatStateFrame:SetScript("OnDragStop", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:857:49");
            self:StopMovingOrSizing()
        local x, y = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            local dx = x - ux
            local dy = y - uy
            local db = EnsureGameplayDefaults()
            db.combatStateOffsetX = dx
            db.combatStateOffsetY = dy
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:857:49"); end)
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
        combatEventFrame = CreateFrame("Frame", "MSUF_CombatStateEventFrame", UIParent)
        -- Events are registered/unregistered in ns.MSUF_RequestGameplayApply() for performance.
        combatEventFrame:UnregisterAllEvents()
local function MSUF_CombatState_OnEvent(_, event) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CombatState_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:893:6");
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CombatState_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:893:6"); return
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
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CombatState_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:893:6"); return
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
            C_Timer_After(duration, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:945:36");
                local g2 = GetGameplayDBFast()
                if combatStateText and g2 and g2.enableCombatStateText then
                    combatStateText:SetText("")
                    combatStateText:Hide()
                    MSUF_CombatState_SetClickThrough(false)
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:945:36"); end)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leave combat: "-Combat" OR First Dance timer
        firstDanceActive = false
        firstDanceEndTime = 0
        firstDanceLastText = nil

        if g.enableFirstDanceTimer then
            StartFirstDanceWindow()
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CombatState_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:893:6"); return
        end

        if not wantState then
            if combatStateText then
                combatStateText:SetText("")
                combatStateText:Hide()
            end
            MSUF_CombatState_SetClickThrough(false)
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CombatState_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:893:6"); return
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
            C_Timer_After(duration, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:988:36");
                local g2 = GetGameplayDBFast()
                if combatStateText and g2 and g2.enableCombatStateText then
                    combatStateText:SetText("")
                    combatStateText:Hide()
                    MSUF_CombatState_SetClickThrough(false)
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:988:36"); end)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CombatState_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:893:6"); end
combatEventFrame:SetScript("OnEvent", MSUF_CombatState_OnEvent)
    end

Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureCombatStateText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:833:24"); end

------------------------------------------------------
-- "First Dance" countdown tick
------------------------------------------------------
local function _TickFirstDance() Perfy_Trace(Perfy_GetTime(), "Enter", "_TickFirstDance file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1007:6");
    if not firstDanceActive then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_TickFirstDance file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1007:6"); return
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "_TickFirstDance file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1007:6"); return
    end

    if not combatStateText and EnsureCombatStateText then
        EnsureCombatStateText()
    end

    if not combatStateText then
        MSUF_CombatState_SetClickThrough(false)
        Perfy_Trace(Perfy_GetTime(), "Leave", "_TickFirstDance file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1007:6"); return
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "_TickFirstDance file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1007:6"); return
    end

    local text = string_format("First Dance: %.1f", remaining)
    if text ~= firstDanceLastText then
        firstDanceLastText = text
        combatStateText:SetText(text)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "_TickFirstDance file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1007:6"); end


EnsureFirstDanceTaskRegistered = function() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureFirstDanceTaskRegistered file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1062:33");
    if ns and ns._MSUF_FirstDanceTaskRegistered then
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureFirstDanceTaskRegistered file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1062:33"); return
    end
    if not combatStateFrame then
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureFirstDanceTaskRegistered file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1062:33"); return
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
        combatStateFrame:SetScript("OnUpdate", function(self, elapsed) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1085:47");
            _TickFirstDance()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1085:47"); end)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureFirstDanceTaskRegistered file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1062:33"); end



------------------------------------------------------
-- Combat crosshair (simple green crosshair at player feet)
------------------------------------------------------

-- Returns true if any Blizzard "find yourself" / self highlight or
-- personal nameplate setting is active so we let the crosshair
-- follow the camera.
local function MSUF_ShouldCrosshairFollowCamera() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ShouldCrosshairFollowCamera file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1100:6");
    if not GetCVar then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShouldCrosshairFollowCamera file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1100:6"); return false
    end

    -- 1) Klassischer Self-Highlight-Modus (Circle / Outline / Icon)
    local mode = tonumber(GetCVar("findYourselfMode") or "0") or 0
    if mode > 0 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShouldCrosshairFollowCamera file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1100:6"); return true
    end

    if GetCVarBool then
        -- Zusätzliche Flags
        if GetCVarBool("findYourselfModeAll")
        or GetCVarBool("findYourselfModeAlways")
        or GetCVarBool("findYourselfModeCombat") then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShouldCrosshairFollowCamera file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1100:6"); return true
        end
    end

    -- 2) Eigene Nameplate / Personal Resource Display
    if GetCVarBool and (GetCVarBool("nameplateShowSelf") or GetCVarBool("nameplateShowAll")) then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShouldCrosshairFollowCamera file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1100:6"); return true
    end

    -- 3) Failsafe: Personal Nameplate-Frame ist sichtbar
    local personal = _G.NamePlatePersonalFrame
    if personal and personal:IsShown() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShouldCrosshairFollowCamera file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1100:6"); return true
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShouldCrosshairFollowCamera file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1100:6"); return false
end

-- Re-anchor combat crosshair. It will only follow the camera when
-- Self Highlight / nameplates are active; otherwise we fall back to
-- the classic screen-center position.
local function MSUF_AnchorCombatCrosshair() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_AnchorCombatCrosshair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1137:6");
    if not combatCrosshairFrame then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_AnchorCombatCrosshair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1137:6"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_AnchorCombatCrosshair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1137:6"); end

-- Forward declaration so calls above resolve to local, not _G
local MSUF_UpdateCombatCrosshairRangeColor
local function EnsureCombatCrosshair() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureCombatCrosshair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1197:6");
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

            local function MSUF_CombatCrosshair_OnEvent(_, event, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CombatCrosshair_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1223:18");
                local arg1 = ...
                local g2 = GetGameplayDBFast()
                if not g2.enableCombatCrosshair or not combatCrosshairFrame then
                    if combatCrosshairFrame then
                        combatCrosshairFrame:Hide()
                    end
                    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CombatCrosshair_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1223:18"); return
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
                                C_Timer_After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1261:49");
                                    if combatCrosshairFrame then
                                        combatCrosshairFrame._msufAnchorPending = nil
                                    end
                                    MSUF_AnchorCombatCrosshair()
                                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1261:49"); end)
                            else
                                combatCrosshairFrame._msufAnchorPending = nil
                                MSUF_AnchorCombatCrosshair()
                            end
                        end
                    end
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CombatCrosshair_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1223:18"); end

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
        umRange:Register("MSUF_GAMEPLAY_CROSSHAIR_RANGE", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1319:58");
            if not combatCrosshairFrame or not combatCrosshairFrame:IsShown() then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1319:58"); return
            end

            -- No DB reads in the hotpath: rely on cached flags/spellID from Apply.
            if not combatCrosshairFrame._msufUseRangeColor or (combatCrosshairFrame._msufRangeSpellID or 0) <= 0 then
                -- Neutralize and stop ticking until config becomes valid again
                MSUF_UpdateCombatCrosshairRangeColor()
                umRange:SetEnabled("MSUF_GAMEPLAY_CROSSHAIR_RANGE", false)
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1319:58"); return
            end

            if not MSUF_CrosshairHasValidTarget() then
                -- No valid target: revert to neutral and stop the background tick until a new target appears
                MSUF_UpdateCombatCrosshairRangeColor()
                umRange:SetEnabled("MSUF_GAMEPLAY_CROSSHAIR_RANGE", false)
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1319:58"); return
            end

            MSUF_UpdateCombatCrosshairRangeColor()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1319:58"); end, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1340:13");
            return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1340:13", (combatCrosshairFrame and combatCrosshairFrame._msufRangeTickInterval) or 0.25)
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
            combatCrosshairFrame:SetScript("OnUpdate", function(self, elapsed) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1360:55");
                if not self:IsShown() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1360:55"); return end
                local g3 = EnsureGameplayDefaults()
                if not g3.enableCombatCrosshair or not g3.enableCombatCrosshairMeleeRangeColor then
                    self:SetScript("OnUpdate", nil)
                    self.MSUF_RangeOnUpdate = nil
                    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1360:55"); return
                end
                self.MSUF_RangeElapsed = (self.MSUF_RangeElapsed or 0) + (elapsed or 0)
                if self.MSUF_RangeElapsed < 0.15 then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1360:55"); return end
                self.MSUF_RangeElapsed = 0
                MSUF_UpdateCombatCrosshairRangeColor()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1360:55"); end)
        end
    else
        if combatCrosshairFrame.MSUF_RangeOnUpdate then
            combatCrosshairFrame:SetScript("OnUpdate", nil)
            combatCrosshairFrame.MSUF_RangeOnUpdate = nil
        end
    end
end

    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureCombatCrosshair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1197:6"); return combatCrosshairFrame
end

-- Lock / unlock helper
local function ApplyLockState() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyLockState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1388:6");
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
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyLockState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1388:6"); end



-- Combat Timer anchor helpers
local function _MSUF_ValidateCombatTimerAnchor(v) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_ValidateCombatTimerAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1412:6");
    if v == "player" or v == "target" or v == "focus" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ValidateCombatTimerAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1412:6"); return v
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ValidateCombatTimerAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1412:6"); return "none"
end

local function _MSUF_GetUnitFrameForAnchor(key) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_GetUnitFrameForAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1419:6");
    if not key or key == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetUnitFrameForAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1419:6"); return nil end
    local list = _G and _G.MSUF_UnitFrames
    if list and list[key] then
        return Perfy_Trace_Passthrough("Leave", "_MSUF_GetUnitFrameForAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1419:6", list[key])
    end
    local gname = "MSUF_" .. key
    local f = _G and _G[gname]
    if f then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetUnitFrameForAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1419:6"); return f
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetUnitFrameForAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1419:6"); return nil
end

local function _MSUF_GetCombatTimerAnchorFrame(g) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_GetCombatTimerAnchorFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1433:6");
    local key = _MSUF_ValidateCombatTimerAnchor(g and g.combatTimerAnchor)
    if key == "none" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetCombatTimerAnchorFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1433:6"); return UIParent
    end
    local f = _MSUF_GetUnitFrameForAnchor(key)
    if f and f.GetCenter then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetCombatTimerAnchorFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1433:6"); return f
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetCombatTimerAnchorFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1433:6"); return UIParent
end

local function MSUF_Gameplay_ApplyCombatTimerAnchor(g) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Gameplay_ApplyCombatTimerAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1445:6");
    if not combatFrame then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Gameplay_ApplyCombatTimerAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1445:6"); return
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
            C_Timer.After(0.2, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1461:31");
                if combatFrame then
                    combatFrame._msufAnchorRetryPending = nil
                    MSUF_Gameplay_ApplyCombatTimerAnchor()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1461:31"); end)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Gameplay_ApplyCombatTimerAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1445:6"); end


-- Export so the main file can call this from UpdateAllFonts()
function ns.MSUF_ApplyGameplayFontFromGlobal() Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_ApplyGameplayFontFromGlobal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1473:0");
    ApplyFontToCounter()
Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_ApplyGameplayFontFromGlobal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1473:0"); end

local function CreateCombatTimerFrame() Perfy_Trace(Perfy_GetTime(), "Enter", "CreateCombatTimerFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1477:6");
    if combatFrame then
        Perfy_Trace(Perfy_GetTime(), "Leave", "CreateCombatTimerFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1477:6"); return combatFrame
    end

    local g = EnsureGameplayDefaults()

    combatFrame = CreateFrame("Frame", "MSUF_CombatTimerFrame", UIParent)
    combatFrame:SetSize(220, 60)
    MSUF_Gameplay_ApplyCombatTimerAnchor(g)
    combatFrame:SetFrameStrata("DIALOG")
    combatFrame:SetClampedToScreen(true)
    combatFrame:SetMovable(true)
    combatFrame:RegisterForDrag("LeftButton")

    combatFrame:SetScript("OnDragStart", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1492:41");
        local gd = EnsureGameplayDefaults()
        if gd.lockCombatTimer then
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1492:41"); return
        end
        self:StartMoving()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1492:41"); end)

    combatFrame:SetScript("OnDragStop", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1500:40");
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        if not x or not y then
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1500:40"); return
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
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1500:40"); return
        end

        db.combatOffsetX = x - ax
        db.combatOffsetY = y - ay
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1500:40"); end)

    combatTimerText = combatFrame:CreateFontString(nil, "OVERLAY")
    combatTimerText:SetPoint("CENTER")

    -- very important: set font BEFORE any SetText call
    ApplyFontToCounter()
    combatTimerText:SetText("")

    -- Apply initial lock state
    ApplyLockState()

    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateCombatTimerFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1477:6"); return combatFrame
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

local function MSUF_BuildMeleeSpellCache() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BuildMeleeSpellCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1550:6");
    if MSUF_MeleeSpellCacheBuilt then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BuildMeleeSpellCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1550:6"); return
    end
    if MSUF_MeleeSpellCacheBuilding then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BuildMeleeSpellCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1550:6"); return
    end

    -- Never build suggestions in combat: defer until we leave combat to avoid stutters in raids.
    if InCombatLockdown and InCombatLockdown() then
        MSUF_MeleeSpellCachePending = true
        if not MSUF_MeleeSpellCacheEventFrame then
            MSUF_MeleeSpellCacheEventFrame = CreateFrame("Frame", "MSUF_MeleeSpellCacheEventFrame", UIParent)
            local function MSUF_MeleeSpellCache_OnEvent() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_MeleeSpellCache_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1563:18");
                if not MSUF_MeleeSpellCachePending then
                    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_MeleeSpellCache_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1563:18"); return
                end
                MSUF_MeleeSpellCachePending = false
                MSUF_MeleeSpellCacheEventFrame:UnregisterAllEvents()
                MSUF_BuildMeleeSpellCache()
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_MeleeSpellCache_OnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1563:18"); end
            MSUF_MeleeSpellCacheEventFrame:SetScript("OnEvent", MSUF_MeleeSpellCache_OnEvent)

        end
        MSUF_MeleeSpellCacheEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BuildMeleeSpellCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1550:6"); return
    end

    MSUF_MeleeSpellCacheBuilding = true
    MSUF_MeleeSpellCachePending = false
    MSUF_MeleeSpellCache = {}

    local seen = {}
    local maxMeleeRange = 8 -- include short melee-ish abilities (5y/6y/8y)
    local iter = 0
    local YIELD_EVERY = 250

    local function YieldMaybe() Perfy_Trace(Perfy_GetTime(), "Enter", "YieldMaybe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1587:10");
        iter = iter + 1
        if (iter % YIELD_EVERY) == 0 then
            coroutine.yield()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "YieldMaybe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1587:10"); end

    local function AddSpell(spellID, name, maxRange) Perfy_Trace(Perfy_GetTime(), "Enter", "AddSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1594:10");
        if not spellID or not name or seen[spellID] then Perfy_Trace(Perfy_GetTime(), "Leave", "AddSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1594:10"); return end
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "AddSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1594:10"); end

    local function BuildBody() Perfy_Trace(Perfy_GetTime(), "Enter", "BuildBody file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1611:10");
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
            table_sort(MSUF_MeleeSpellCache, function(a, b) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1721:45");
                return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1721:45", a.lower < b.lower)
            end)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "BuildBody file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1611:10"); end

    -- Chunked build via coroutine to avoid a single-frame spellbook scan spike.
    local co = coroutine.create(BuildBody)

    local function FinishBuild() Perfy_Trace(Perfy_GetTime(), "Enter", "FinishBuild file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1730:10");
        MSUF_MeleeSpellCacheBuilding = false
        MSUF_MeleeSpellCacheBuilt = true
        MSUF_MeleeSpellCachePending = false
        if MSUF_MeleeSpellCacheEventFrame then
            MSUF_MeleeSpellCacheEventFrame:UnregisterAllEvents()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "FinishBuild file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1730:10"); end

    local function Step() Perfy_Trace(Perfy_GetTime(), "Enter", "Step file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1739:10");
        if not co then
            FinishBuild()
            Perfy_Trace(Perfy_GetTime(), "Leave", "Step file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1739:10"); return
        end

        local ok = coroutine.resume(co)
        if not ok then
            -- Fail safe: never spam errors; just mark built so we don't retry every keystroke.
            -- Suggestions will simply be empty.
            MSUF_MeleeSpellCache = MSUF_MeleeSpellCache or {}
            FinishBuild()
            Perfy_Trace(Perfy_GetTime(), "Leave", "Step file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1739:10"); return
        end

        if coroutine.status(co) == "dead" then
            FinishBuild()
            Perfy_Trace(Perfy_GetTime(), "Leave", "Step file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1739:10"); return
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "Step file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1739:10"); end

    Step()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BuildMeleeSpellCache file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1550:6"); end

-- Track which spell IDs currently have range checks enabled (base + potential override)
local MSUF_LastEnabledMeleeRangeSpellID = 0
local MSUF_LastEnabledMeleeRangeSpellID_Override = 0

local function MSUF_GetOverrideSpellID(spellID) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetOverrideSpellID file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1778:6");
    if not (C_Spell and C_Spell.GetOverrideSpell) then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetOverrideSpellID file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1778:6"); return 0
    end
    local ok, overrideID = MSUF_FastCall(C_Spell.GetOverrideSpell, spellID)
    if ok and type(overrideID) == "number" and overrideID > 0 and overrideID ~= spellID then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetOverrideSpellID file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1778:6"); return overrideID
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetOverrideSpellID file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1778:6"); return 0
end

local function MSUF_SetEnabledMeleeRangeCheck(spellID) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetEnabledMeleeRangeCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1789:6");
    if not (C_Spell and C_Spell.EnableSpellRangeCheck) then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetEnabledMeleeRangeCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1789:6"); return
    end

    spellID = tonumber(spellID) or 0
    local overrideID = 0
    if spellID > 0 then
        overrideID = MSUF_GetOverrideSpellID(spellID)
    end

    if spellID == MSUF_LastEnabledMeleeRangeSpellID and overrideID == MSUF_LastEnabledMeleeRangeSpellID_Override then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetEnabledMeleeRangeCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1789:6"); return
    end

    local function Disable(id) Perfy_Trace(Perfy_GetTime(), "Enter", "Disable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1804:10");
        if id and id > 0 then
            MSUF_FastCall(C_Spell.EnableSpellRangeCheck, id, false)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "Disable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1804:10"); end

    local function Enable(id) Perfy_Trace(Perfy_GetTime(), "Enter", "Enable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1810:10");
        if id and id > 0 then
            MSUF_FastCall(C_Spell.EnableSpellRangeCheck, id, true)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "Enable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1810:10"); end

    -- Disable old checks (override first, then base)
    Disable(MSUF_LastEnabledMeleeRangeSpellID_Override)
    Disable(MSUF_LastEnabledMeleeRangeSpellID)

    MSUF_LastEnabledMeleeRangeSpellID = spellID
    MSUF_LastEnabledMeleeRangeSpellID_Override = overrideID

    -- Enable new checks
    Enable(spellID)
    Enable(overrideID)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetEnabledMeleeRangeCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1789:6"); end

local function MSUF_IsUnitInMeleeRange(unit, spellID) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_IsUnitInMeleeRange file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1828:6");
    spellID = tonumber(spellID) or 0
    if spellID <= 0 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsUnitInMeleeRange file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1828:6"); return false
    end
    if not (C_Spell and C_Spell.IsSpellInRange) then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsUnitInMeleeRange file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1828:6"); return false
    end

    -- Some specs/classes (notably DH) use override spells (e.g. Chaos Strike -> Annihilation).
    -- Try the override ID first, then fall back to the base ID.
    local overrideID = MSUF_GetOverrideSpellID(spellID)
    if overrideID and overrideID > 0 then
        local okOverride = C_Spell.IsSpellInRange(overrideID, unit)
        if okOverride == true or okOverride == 1 then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsUnitInMeleeRange file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1828:6"); return true
        end
    end

    local ok = C_Spell.IsSpellInRange(spellID, unit)
    -- IMPORTANT: nil = cannot be evaluated => NOT in range for the filter
    return Perfy_Trace_Passthrough("Leave", "MSUF_IsUnitInMeleeRange file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1828:6", ok == true or ok == 1)
end

-- Crosshair range driver helpers (perf):
-- 1) Disable background range ticks unless we're in combat AND have a valid hostile target.
-- 2) Coalesce bursts of events (target changed / range updates) into a single refresh per frame.
MSUF_CrosshairHasValidTarget = function() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CrosshairHasValidTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1855:31");
    return Perfy_Trace_Passthrough("Leave", "MSUF_CrosshairHasValidTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1855:31", UnitExists and UnitExists("target")
        and UnitCanAttack and UnitCanAttack("player", "target")
        and UnitIsDeadOrGhost and (not UnitIsDeadOrGhost("target")))
end

local function MSUF_SetCrosshairRangeTaskEnabled(enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetCrosshairRangeTaskEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1861:6");
    local um = MSUF_GetUpdateManager()
    if um and um.SetEnabled then
        um:SetEnabled("MSUF_GAMEPLAY_CROSSHAIR_RANGE", enabled and true or false)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetCrosshairRangeTaskEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1861:6"); end

MSUF_RefreshCrosshairRangeTaskEnabled = function() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RefreshCrosshairRangeTaskEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1868:40");
    -- Hard-disable background work unless everything is in the "fast path" state.
    if not combatCrosshairFrame or not combatCrosshairFrame.IsShown or (not combatCrosshairFrame:IsShown()) then
        MSUF_SetCrosshairRangeTaskEnabled(false)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RefreshCrosshairRangeTaskEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1868:40"); return
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RefreshCrosshairRangeTaskEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1868:40"); return
    end

    if not MSUF_CrosshairHasValidTarget() then
        MSUF_SetCrosshairRangeTaskEnabled(false)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RefreshCrosshairRangeTaskEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1868:40"); return
    end

    -- Dynamic interval: while in combat + valid target, tick fast.
    combatCrosshairFrame._msufRangeTickInterval = 0.25
    MSUF_SetCrosshairRangeTaskEnabled(true)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RefreshCrosshairRangeTaskEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1868:40"); end

local function MSUF_RunCrosshairRangeRefresh() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RunCrosshairRangeRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1900:6");
    if ns then
        ns._MSUF_CrosshairRangeRefreshPending = nil
    end

    -- If the crosshair isn't visible, don't burn work; just ensure the background tick is off.
    if not combatCrosshairFrame or not combatCrosshairFrame.IsShown or (not combatCrosshairFrame:IsShown()) then
        MSUF_RefreshCrosshairRangeTaskEnabled()
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RunCrosshairRangeRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1900:6"); return
    end

    MSUF_UpdateCombatCrosshairRangeColor()
    MSUF_RefreshCrosshairRangeTaskEnabled()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RunCrosshairRangeRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1900:6"); end

MSUF_RequestCrosshairRangeRefresh = function() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RequestCrosshairRangeRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1915:36");
    if not ns then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RequestCrosshairRangeRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1915:36"); return end
    if ns._MSUF_CrosshairRangeRefreshPending then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RequestCrosshairRangeRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1915:36"); return end
    ns._MSUF_CrosshairRangeRefreshPending = true

    if C_Timer_After then
        C_Timer_After(0, MSUF_RunCrosshairRangeRefresh)
    else
        MSUF_RunCrosshairRangeRefresh()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RequestCrosshairRangeRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1915:36"); end

-- Update combat crosshair color based on melee range to current target.
-- Uses the shared melee spell ID.
MSUF_UpdateCombatCrosshairRangeColor = function() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_UpdateCombatCrosshairRangeColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1929:39");
    if not combatCrosshairFrame or not combatCrosshairFrame.horiz or not combatCrosshairFrame.vert then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateCombatCrosshairRangeColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1929:39"); return
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateCombatCrosshairRangeColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1929:39"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateCombatCrosshairRangeColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:1929:39"); end
------------------------------------------------------
-- Public helpers for main addon
------------------------------------------------------

------------------------------------------------------
-- Gameplay "drivers" (perf + maintainability)
-- These functions own event registration and background tasks for each feature.
-- They make it safe to split this file later without changing behavior.
------------------------------------------------------
local function MSUF_Gameplay_ApplyCombatStateText(g) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Gameplay_ApplyCombatStateText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2017:6");
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Gameplay_ApplyCombatStateText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2017:6"); end

local function MSUF_Gameplay_ApplyCombatCrosshair(g) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Gameplay_ApplyCombatCrosshair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2096:6");

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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Gameplay_ApplyCombatCrosshair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2096:6"); end



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

    local function _IsPlayerShaman() Perfy_Trace(Perfy_GetTime(), "Enter", "_IsPlayerShaman file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2161:10");
        if UnitClass then
            local _, class = UnitClass("player")
            return Perfy_Trace_Passthrough("Leave", "_IsPlayerShaman file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2161:10", class == "SHAMAN")
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_IsPlayerShaman file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2161:10"); return false
    end


    local function _ToNumberSafe(v) Perfy_Trace(Perfy_GetTime(), "Enter", "_ToNumberSafe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2170:10");
        if type(v) == "number" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_ToNumberSafe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2170:10"); return v
        end
        if v == nil then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_ToNumberSafe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2170:10"); return nil
        end
        local ok, n = pcall(tonumber, v)
        if ok and type(n) == "number" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_ToNumberSafe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2170:10"); return n
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_ToNumberSafe file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2170:10"); return nil
    end
    local function _FormatRemaining(sec) Perfy_Trace(Perfy_GetTime(), "Enter", "_FormatRemaining file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2183:10");
        if not sec or sec <= 0 then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_FormatRemaining file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2183:10"); return ""
        end
        if sec < 10 then
            return Perfy_Trace_Passthrough("Leave", "_FormatRemaining file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2183:10", string_format("%.1f", sec))
        end
        if sec < 60 then
            return Perfy_Trace_Passthrough("Leave", "_FormatRemaining file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2183:10", string_format("%d", math.floor(sec + 0.5)))
        end
        local m = math.floor(sec / 60)
        local s = math.floor(sec - (m * 60) + 0.5)
        if s >= 60 then
            m = m + 1
            s = 0
        end
        return Perfy_Trace_Passthrough("Leave", "_FormatRemaining file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2183:10", string_format("%d:%02d", m, s))
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

local function _MSUF_RoundInt(v) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_RoundInt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2213:6");
    if type(v) ~= "number" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_RoundInt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2213:6"); return 0
    end
    if v >= 0 then
        return Perfy_Trace_Passthrough("Leave", "_MSUF_RoundInt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2213:6", math.floor(v + 0.5))
    end
    return Perfy_Trace_Passthrough("Leave", "_MSUF_RoundInt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2213:6", math.ceil(v - 0.5))
end

local function _ApplyTotemsAnchorOnly(g, offX, offY) Perfy_Trace(Perfy_GetTime(), "Enter", "_ApplyTotemsAnchorOnly file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2223:6");
    if not totemsFrame then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_ApplyTotemsAnchorOnly file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2223:6"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "_ApplyTotemsAnchorOnly file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2223:6"); end

local function _SetTotemsDragEnabled(on) Perfy_Trace(Perfy_GetTime(), "Enter", "_SetTotemsDragEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2245:6");
    if not totemsFrame then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_SetTotemsDragEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2245:6"); return
    end
    local ov = totemsFrame._msufDragOverlay
    if not ov then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_SetTotemsDragEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2245:6"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "_SetTotemsDragEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2245:6"); end

    local function _EnsureTotemsFrame() Perfy_Trace(Perfy_GetTime(), "Enter", "_EnsureTotemsFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2265:10");
        if totemsFrame then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_EnsureTotemsFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2265:10"); return totemsFrame
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

    ov:SetScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2319:28");
        if self._msufHi then self._msufHi:Show() end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Totems Preview", 1, 1, 1)
            GameTooltip:AddLine("Drag to move.", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("Use X/Y offsets for fine tuning.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2319:28"); end)
    ov:SetScript("OnLeave", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2329:28");
        if self._msufHi then self._msufHi:Hide() end
        if GameTooltip then GameTooltip:Hide() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2329:28"); end)

    ov:SetScript("OnMouseDown", function(self, btn) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2334:32");
        if btn ~= "LeftButton" then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2334:32"); return end

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

        self:SetScript("OnUpdate", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2353:35");
            if not self._msufDragging then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2353:35"); return end
            local g = self._msufDragG
            if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2353:35"); return end

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
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2353:35"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2334:32"); end)

    ov:SetScript("OnMouseUp", function(self, btn) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2385:30");
        if btn ~= "LeftButton" then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2385:30"); return end
        self._msufDragging = nil
        self:SetScript("OnUpdate", nil)

        local opt = _G and _G.MSUF_GameplayPanel
        if opt and opt.MSUF_SyncTotemOffsetSliders then
            opt:MSUF_SyncTotemOffsetSliders()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2385:30"); end)

    totemsFrame._msufDragOverlay = ov
end

totemsFrame:Hide()
        Perfy_Trace(Perfy_GetTime(), "Leave", "_EnsureTotemsFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2265:10"); return totemsFrame
    end

    local function _ClearTotemsPreview() Perfy_Trace(Perfy_GetTime(), "Enter", "_ClearTotemsPreview file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2403:10");
        if totemsFrame then
            totemsFrame._msufPreviewActive = nil
        end
        _SetTotemsDragEnabled(false)
    Perfy_Trace(Perfy_GetTime(), "Leave", "_ClearTotemsPreview file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2403:10"); end

    local function _ApplyTotemsPreview(g) Perfy_Trace(Perfy_GetTime(), "Enter", "_ApplyTotemsPreview file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2410:10");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "_ApplyTotemsPreview file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2410:10"); end

    local function _ApplyTotemsLayout(g) Perfy_Trace(Perfy_GetTime(), "Enter", "_ApplyTotemsLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2447:10");
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
Perfy_Trace(Perfy_GetTime(), "Leave", "_ApplyTotemsLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2447:10"); end

local function _FormatTotemTime(left) Perfy_Trace(Perfy_GetTime(), "Enter", "_FormatTotemTime file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2540:6");
    -- Midnight/Beta secret-safe:
    -- - Never directly compare/arithmetic on values that may be "secret".
    -- - Always have a simple fallback: 1 decimal seconds.
    if left == nil then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_FormatTotemTime file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2540:6"); return ""
    end

    local okSimple, simple = pcall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2548:35");
        return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2548:35", string.format("%.1fs", left))
    end)
    if not okSimple then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_FormatTotemTime file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2540:6"); return ""
    end

    -- Apply nicer rules ONLY if comparisons/math are safe.
    local okNum, n = pcall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2556:27"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2556:27", tonumber(left)) end)
    if not okNum or type(n) ~= "number" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_FormatTotemTime file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2540:6"); return simple
    end

    local okLT10, isLT10 = pcall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2561:33"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2561:33", n < 10) end)
    if not okLT10 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_FormatTotemTime file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2540:6"); return simple
    end
    if isLT10 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_FormatTotemTime file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2540:6"); return simple
    end

    local okLT60, isLT60 = pcall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2569:33"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2569:33", n < 60) end)
    if not okLT60 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_FormatTotemTime file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2540:6"); return simple
    end
    if isLT60 then
        local okRound, secs = pcall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2574:36"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2574:36", math.floor(n + 0.5)) end)
        if okRound and type(secs) == "number" then
            return Perfy_Trace_Passthrough("Leave", "_FormatTotemTime file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2540:6", string.format("%ds", secs))
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_FormatTotemTime file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2540:6"); return simple
    end

    local okMS, out = pcall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2581:28");
        local m = math.floor(n / 60)
        local s = math.floor((n - (m * 60)) + 0.5)
        if s >= 60 then
            m = m + 1
            s = 0
        end
        return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2581:28", string.format("%d:%02d", m, s))
    end)
    if okMS and type(out) == "string" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_FormatTotemTime file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2540:6"); return out
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "_FormatTotemTime file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2540:6"); return simple
end

local function _PickTotemTickInterval(minLeft) Perfy_Trace(Perfy_GetTime(), "Enter", "_PickTotemTickInterval file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2597:6");
    -- Secret-safe tick selection: only branch on numeric thresholds when safe.
    local okNum, n = pcall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2599:27"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2599:27", tonumber(minLeft)) end)
    if not okNum or type(n) ~= "number" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_PickTotemTickInterval file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2597:6"); return 0.50
    end

    local okLT10, isLT10 = pcall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2604:33"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2604:33", n < 10) end)
    if okLT10 and isLT10 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_PickTotemTickInterval file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2597:6"); return 0.10
    end

    local okLT60, isLT60 = pcall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2609:33"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2609:33", n < 60) end)
    if okLT60 and isLT60 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_PickTotemTickInterval file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2597:6"); return 0.50
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "_PickTotemTickInterval file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2597:6"); return 1.00
end

local function _UpdateTotemsNow(g) Perfy_Trace(Perfy_GetTime(), "Enter", "_UpdateTotemsNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2617:6");
    if not totemsFrame then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_UpdateTotemsNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2617:6"); return false
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

    Perfy_Trace(Perfy_GetTime(), "Leave", "_UpdateTotemsNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2617:6"); return any
end


local function _TickTotemText() Perfy_Trace(Perfy_GetTime(), "Enter", "_TickTotemText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2690:6");
    local g = GetGameplayDBFast()
    if not g or not g.enablePlayerTotems or not g.playerTotemsShowText then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_TickTotemText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2690:6"); return
    end

    if not totemsFrame or not totemsFrame:IsShown() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_TickTotemText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2690:6"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "_TickTotemText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2690:6"); end


    local function _UpdateTotemTickEnabled(g, any) Perfy_Trace(Perfy_GetTime(), "Enter", "_UpdateTotemTickEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2731:10");
        local um = MSUF_GetUpdateManager()
        if not um or not um.Register or not um.SetEnabled then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_UpdateTotemTickEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2731:10"); return
        end

        if not ns._MSUF_PlayerTotemTaskRegistered then
            ns._MSUF_PlayerTotemTaskRegistered = true
            local function _Interval() Perfy_Trace(Perfy_GetTime(), "Enter", "_Interval file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2739:18"); return Perfy_Trace_Passthrough("Leave", "_Interval file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2739:18", (ns._MSUF_PlayerTotemsTickInterval or 0.50)) end -- dynamic countdown interval
            um:Register("MSUF_GAMEPLAY_PLAYERTOTEMS", _TickTotemText, _Interval, 90)
        end

        local enableTick = (g and g.enablePlayerTotems and g.playerTotemsShowText and any) and true or false
        um:SetEnabled("MSUF_GAMEPLAY_PLAYERTOTEMS", enableTick)
    Perfy_Trace(Perfy_GetTime(), "Leave", "_UpdateTotemTickEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2731:10"); end

    local function _RefreshTotems() Perfy_Trace(Perfy_GetTime(), "Enter", "_RefreshTotems file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2747:10");
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
            Perfy_Trace(Perfy_GetTime(), "Leave", "_RefreshTotems file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2747:10"); return
        else
            _ClearTotemsPreview()
        end

        if (not g.enablePlayerTotems) or (not isShaman) then
            _UpdateTotemTickEnabled(g, false)
            if totemsFrame then
                totemsFrame:Hide()
            end
            lastHasAnyTotem = false
            Perfy_Trace(Perfy_GetTime(), "Leave", "_RefreshTotems file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2747:10"); return
        end

        _EnsureTotemsFrame()
        _ApplyTotemsLayout(g)
        local any = _UpdateTotemsNow(g)
        _UpdateTotemTickEnabled(g, any)
    Perfy_Trace(Perfy_GetTime(), "Leave", "_RefreshTotems file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2747:10"); end

    local function _EnsureTotemEvents() Perfy_Trace(Perfy_GetTime(), "Enter", "_EnsureTotemEvents file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2781:10");
        if totemEventFrame then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_EnsureTotemEvents file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2781:10"); return
        end

        totemEventFrame = CreateFrame("Frame", "MSUF_PlayerTotemsEventFrame", UIParent)
        totemEventFrame:SetScript("OnEvent", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2787:45");
            _RefreshTotems()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2787:45"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "_EnsureTotemEvents file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2781:10"); end

    function GameplayFeatures_PlayerTotems_Apply(g) Perfy_Trace(Perfy_GetTime(), "Enter", "GameplayFeatures_PlayerTotems_Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2792:4");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "GameplayFeatures_PlayerTotems_Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2792:4"); end

    -- Public escape hatch: Options / other modules can force a refresh without poking locals.
    _G.MSUF_PlayerTotems_ForceRefresh = _RefreshTotems

    function ns.MSUF_PlayerTotems_TogglePreview() Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_PlayerTotems_TogglePreview file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2810:4");
        _previewWanted = not _previewWanted
        _RefreshTotems()
    Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_PlayerTotems_TogglePreview file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2810:4"); end

    function ns.MSUF_PlayerTotems_IsPreviewActive() Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_PlayerTotems_IsPreviewActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2815:4");
        return Perfy_Trace_Passthrough("Leave", "ns.MSUF_PlayerTotems_IsPreviewActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2815:4", (_previewWanted and true) or false)
    end

end


-- Feature tables (single-file modules) for readability and safer future refactors
local GameplayFeatures = {
    CombatTimer     = {},
    CombatStateText = {},
    CombatCrosshair = {},
    PlayerTotems    = {},
}

function GameplayFeatures.CombatTimer.Apply(g) Perfy_Trace(Perfy_GetTime(), "Enter", "CombatTimer.Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2830:0");
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
Perfy_Trace(Perfy_GetTime(), "Leave", "CombatTimer.Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2830:0"); end

GameplayFeatures.CombatStateText.Apply = MSUF_Gameplay_ApplyCombatStateText
GameplayFeatures.CombatCrosshair.Apply = MSUF_Gameplay_ApplyCombatCrosshair

GameplayFeatures.PlayerTotems.Apply = GameplayFeatures_PlayerTotems_Apply

local GameplayFeatureOrder = { "CombatTimer", "CombatStateText", "CombatCrosshair", "PlayerTotems" }

local function Gameplay_ApplyAllFeatures(g) Perfy_Trace(Perfy_GetTime(), "Enter", "Gameplay_ApplyAllFeatures file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2852:6");
    for i = 1, #GameplayFeatureOrder do
        local key = GameplayFeatureOrder[i]
        local f = GameplayFeatures[key]
        if f and f.Apply then
            f.Apply(g)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "Gameplay_ApplyAllFeatures file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2852:6"); end

function ns.MSUF_RequestGameplayApply() Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_RequestGameplayApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2862:0");
    local g = EnsureGameplayDefaults()


    Gameplay_ApplyAllFeatures(g)

-- Centralized throttling: register combat-timer ticks in the global MSUF_UpdateManager
    local um = MSUF_GetUpdateManager()
    if um and um.Register and um.SetEnabled then
        if not ns._MSUF_GameplayTasksRegistered then
            ns._MSUF_GameplayTasksRegistered = true

            local function _CombatInterval() Perfy_Trace(Perfy_GetTime(), "Enter", "_CombatInterval file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2874:18");
                -- Timer is formatted as mm:ss, so it only changes once per second.
                -- Keeping this at 1.0s reduces CPU in raids without any visible downside.
                Perfy_Trace(Perfy_GetTime(), "Leave", "_CombatInterval file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2874:18"); return 1.0
            end
            um:Register("MSUF_GAMEPLAY_COMBATTIMER", MSUF_Gameplay_TickCombatTimer, _CombatInterval, 90)
        end

        -- Off means off: enable only what is configured
        um:SetEnabled("MSUF_GAMEPLAY_COMBATTIMER", g.enableCombatTimer and true or false)

        -- Make combat timer start immediately on combat start (no 0-1s "lag").
        -- We also set combatStartTime from the event timestamp so the timer isn't permanently behind.
        if not combatTimerEventFrame then
            combatTimerEventFrame = CreateFrame("Frame", "MSUF_CombatTimerEventFrame", UIParent)
            combatTimerEventFrame:SetScript("OnEvent", function(_, event) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2889:55");
                local gd = GetGameplayDBFast()
                if not gd or not gd.enableCombatTimer then
                    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2889:55"); return
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
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2889:55"); end)
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
Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_RequestGameplayApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2862:0"); end


-- Backwards-compatible entrypoint used by other modules (e.g. Colors)
-- Apply all Gameplay visuals immediately (frames + fonts + colors).
function ns.MSUF_ApplyGameplayVisuals() Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_ApplyGameplayVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2955:0");
    -- This file also uses MSUF_RequestGameplayApply as the canonical apply path.
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_ApplyGameplayVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2955:0"); end


------------------------------------------------------
-- Options panel
------------------------------------------------------
function ns.MSUF_RegisterGameplayOptions_Full(parentCategory) Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_RegisterGameplayOptions_Full file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2966:0");
    local panel = (_G and _G.MSUF_GameplayPanel) or CreateFrame("Frame", "MSUF_GameplayPanel", UIParent)
    panel.name = "Gameplay"

    if panel.__MSUF_GameplayBuilt then
        Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_RegisterGameplayOptions_Full file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2966:0"); return panel
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




    local function RequestApply() Perfy_Trace(Perfy_GetTime(), "Enter", "RequestApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2990:10");
        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "RequestApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2990:10"); end

    local function BindCheck(cb, key, after) Perfy_Trace(Perfy_GetTime(), "Enter", "BindCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2996:10");
        cb:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2997:32");
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2997:32"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "BindCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2996:10"); end

    local function BindSlider(sl, key, roundFunc, after, applyNow) Perfy_Trace(Perfy_GetTime(), "Enter", "BindSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3023:10");
        sl:SetScript("OnValueChanged", function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3024:39");
            -- UI sync (panel:refresh / drag-sync) should not write DB or trigger apply.
            if panel and panel._msufSuppressSliderChanges then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3024:39"); return
            end
            local g = EnsureGameplayDefaults()
            if roundFunc then value = roundFunc(value) end
            g[key] = value
            if after then after(self, g, value) end
            if applyNow then RequestApply() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3024:39"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "BindSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3023:10"); end

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

    b:SetScript("OnClick", function(selfBtn) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3148:27");
        local data = selfBtn.data
        if not data then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3148:27"); return end
        -- Route through the shared selection helper so per-class storage stays in sync.
        MSUF_SelectMeleeSpell(data.id, data.name, true)
        MSUF_SkipMeleeFocusLostResolve = true
        meleeInput:ClearFocus()
        suggestionFrame:Hide()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3148:27"); end)

    suggestionButtons[i] = b
end

local function UpdateSelectedTextFromDB() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateSelectedTextFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3161:6");
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
Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateSelectedTextFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3161:6"); end

local function QuerySuggestions(query) Perfy_Trace(Perfy_GetTime(), "Enter", "QuerySuggestions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3209:6");
    MSUF_BuildMeleeSpellCache()
    if not MSUF_MeleeSpellCache or #MSUF_MeleeSpellCache == 0 then
        return Perfy_Trace_Passthrough("Leave", "QuerySuggestions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3209:6", {})
    end

    local q = string_lower(query or "")
    if q == "" then
        return Perfy_Trace_Passthrough("Leave", "QuerySuggestions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3209:6", {})
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "QuerySuggestions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3209:6"); return out
end


MSUF_SelectMeleeSpell = function(spellID, spellName, preferNameInBox) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SelectMeleeSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3233:24");
    local g = EnsureGameplayDefaults()
    spellID = tonumber(spellID) or 0
    if spellID <= 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SelectMeleeSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3233:24"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SelectMeleeSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3233:24"); end

local function MSUF_ResolveTypedMeleeSpell(text) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ResolveTypedMeleeSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3265:6");
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResolveTypedMeleeSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3265:6"); return nil end

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
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResolveTypedMeleeSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3265:6"); return asNum, name
    end

    local q = string_lower(text)
    local results = QuerySuggestions(text)
    -- Prefer exact match (case-insensitive)
    for i = 1, #results do
        if results[i] and results[i].lower == q then
            return Perfy_Trace_Passthrough("Leave", "MSUF_ResolveTypedMeleeSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3265:6", results[i].id, results[i].name)
        end
    end
    -- Otherwise, pick first suggestion
    if results[1] then
        return Perfy_Trace_Passthrough("Leave", "MSUF_ResolveTypedMeleeSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3265:6", results[1].id, results[1].name)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResolveTypedMeleeSpell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3265:6"); return nil
end

meleeInput:SetScript("OnEnterPressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3297:39");
    -- If dropdown is open, choose the first visible suggestion; otherwise try resolving typed text.
    local first = suggestionButtons[1] and suggestionButtons[1].data
    if suggestionFrame:IsShown() and first and first.id then
        MSUF_SelectMeleeSpell(first.id, first.name, true)
        suggestionFrame:Hide()
        MSUF_SkipMeleeFocusLostResolve = true
        self:ClearFocus()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3297:39"); return
    end

    local id, name = MSUF_ResolveTypedMeleeSpell(self:GetText())
    if id then
        MSUF_SelectMeleeSpell(id, name, true)
    end
    suggestionFrame:Hide()
    MSUF_SkipMeleeFocusLostResolve = true
    self:ClearFocus()
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3297:39"); end)
meleeInput:SetScript("OnTextChanged", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3316:38");
    if MSUF_SuppressMeleeInputChange then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3316:38"); return end
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3316:38"); return
    end

    local results = QuerySuggestions(txt)
    if #results == 0 then
        suggestionFrame:Hide()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3316:38"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3316:38"); end)

-- Per-class checkbox behavior.
perClassCB:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3367:32");
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
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3367:32"); end)

meleeInput:SetScript("OnEscapePressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3393:40");
    self:ClearFocus()
    suggestionFrame:Hide()
    UpdateSelectedTextFromDB()
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3393:40"); end)

meleeInput:SetScript("OnEditFocusLost", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3399:40");
    suggestionFrame:Hide()
    if MSUF_SkipMeleeFocusLostResolve then
        MSUF_SkipMeleeFocusLostResolve = false
        UpdateSelectedTextFromDB()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3399:40"); return
    end
    local id, name = MSUF_ResolveTypedMeleeSpell(self:GetText())
    if id then
        MSUF_SelectMeleeSpell(id, name, true)
    else
        UpdateSelectedTextFromDB()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3399:40"); end)

    ------------------------------------------------------
    -- Options UI builder helpers (single-file factory)
    -- NOTE: Keep layout pixel-identical by preserving all SetPoint offsets.
    ------------------------------------------------------
    local function _MSUF_Sep(topRef, yOff) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_Sep file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3418:10");
        local t = content:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, 0.15)
        t:SetPoint("TOP", topRef, "BOTTOM", 0, yOff or -24)
        t:SetPoint("LEFT", content, "LEFT", 20, 0)
        t:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        t:SetHeight(1)
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Sep file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3418:10"); return t
    end

    local function _MSUF_Header(sep, text) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_Header file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3428:10");
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        fs:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -10)
        fs:SetText(text)
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Header file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3428:10"); return fs
    end

    local function _MSUF_Label(template, point, rel, relPoint, x, y, text, field) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_Label file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3435:10");
        local fs = content:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
        fs:SetPoint(point, rel, relPoint, x or 0, y or 0)
        fs:SetText(text or "")
        if field then panel[field] = fs end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Label file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3435:10"); return fs
    end

    local function _MSUF_Check(name, point, rel, relPoint, x, y, text, field, key, after) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_Check file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3443:10");
        local cb = CreateFrame("CheckButton", name, content, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint(point, rel, relPoint, x or 0, y or 0)
        cb.Text:SetText(text or "")
        if field then panel[field] = cb end
        if key then BindCheck(cb, key, after) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Check file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3443:10"); return cb
    end


    local function _MSUF_ColorSwatch(name, point, rel, relPoint, x, y, labelText, field, key, defaultRGB, after) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_ColorSwatch file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3453:10");
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

        local function GetDefault() Perfy_Trace(Perfy_GetTime(), "Enter", "GetDefault file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3478:14");
            if type(defaultRGB) == "table" then
                return Perfy_Trace_Passthrough("Leave", "GetDefault file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3478:14", defaultRGB[1] or 1, defaultRGB[2] or 1, defaultRGB[3] or 1)
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetDefault file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3478:14"); return 1, 1, 1
        end

        function btn:MSUF_Refresh() Perfy_Trace(Perfy_GetTime(), "Enter", "btn:MSUF_Refresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3485:8");
            local g = EnsureGameplayDefaults()
            local dr, dg, db = GetDefault()
            local r, g2, b = _MSUF_NormalizeRGB(g and g[key], dr, dg, db)
            self._msufSwatch:SetColorTexture(r, g2, b, 1)
        Perfy_Trace(Perfy_GetTime(), "Leave", "btn:MSUF_Refresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3485:8"); end

        local function ApplyColor(r, g2, b) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3492:14");
            local g = EnsureGameplayDefaults()
            g[key] = { r, g2, b }
            btn:MSUF_Refresh()
            if type(after) == "function" then
                after()
            end
            ns.MSUF_RequestGameplayApply()
        Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3492:14"); end

        btn:SetScript("OnClick", function(self, button) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3502:33");
            if button == "RightButton" then
                local r, g2, b = GetDefault()
                ApplyColor(r, g2, b)
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3502:33"); return
            end

            if not ColorPickerFrame then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3502:33"); return
            end

            local g = EnsureGameplayDefaults()
            local r, g2, b = _MSUF_NormalizeRGB(g and g[key], 1, 1, 1)

            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.previousValues = { r, g2, b }

            ColorPickerFrame.func = function() Perfy_Trace(Perfy_GetTime(), "Enter", "ColorPickerFrame.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3519:36");
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                ApplyColor(nr, ng, nb)
            Perfy_Trace(Perfy_GetTime(), "Leave", "ColorPickerFrame.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3519:36"); end

            ColorPickerFrame.cancelFunc = function(prev) Perfy_Trace(Perfy_GetTime(), "Enter", "ColorPickerFrame.cancelFunc file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3524:42");
                if type(prev) == "table" then
                    ApplyColor(prev[1] or 1, prev[2] or 1, prev[3] or 1)
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "ColorPickerFrame.cancelFunc file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3524:42"); end

            ColorPickerFrame:SetColorRGB(r, g2, b)
            ColorPickerFrame:Show()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3502:33"); end)

        btn:MSUF_Refresh()
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ColorSwatch file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3453:10"); return btn, label
    end

    local function _MSUF_Slider(name, point, rel, relPoint, x, y, width, lo, hi, step, lowText, highText, titleText, field, key, roundFunc, after, applyNow) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_Slider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3538:10");
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Slider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3538:10"); return sl
    end

    local function _MSUF_SliderTextRight(name) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SliderTextRight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3556:10");
        local t = _G[name .. "Text"]
        if t then
            t:ClearAllPoints()
            t:SetPoint("LEFT", _G[name], "RIGHT", 12, 0)
            t:SetJustifyH("LEFT")
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SliderTextRight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3556:10"); end

    local function _MSUF_EditBox(name, point, rel, relPoint, x, y, w, h, field) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_EditBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3565:10");
        local eb = CreateFrame("EditBox", name, content, "InputBoxTemplate")
        eb:SetSize(w or 220, h or 20)
        eb:SetAutoFocus(false)
        eb:SetPoint(point, rel, relPoint, x or 0, y or 0)
        if field then panel[field] = eb end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EditBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3565:10"); return eb
    end
    local function _MSUF_Button(name, point, rel, relPoint, x, y, w, h, text, field, onClick) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_Button file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3573:10");
        local b = CreateFrame("Button", name, content, "UIPanelButtonTemplate")
        b:SetSize(w or 60, h or 20)
        b:SetPoint(point, rel, relPoint, x or 0, y or 0)
        b:SetText(text or "")
        if field then panel[field] = b end
        if type(onClick) == "function" then
            b:SetScript("OnClick", onClick)
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Button file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3573:10"); return b
    end

local function _MSUF_Dropdown(name, point, rel, relPoint, x, y, width, field) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_Dropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3585:6");
    -- Simple UIDropDownMenu-based control (used sparingly in Gameplay to avoid heavy UI scaffolding).
    local dd = CreateFrame("Frame", name, content, "UIDropDownMenuTemplate")
    dd:SetPoint(point, rel, relPoint, x or 0, y or 0)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dd, width or 120)
    end
    if field then
        panel[field] = dd
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Dropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3585:6"); return dd
end


    -- Combat Timer header + separator
    local combatSeparator = _MSUF_Sep(subText, -36)
    local combatHeader = _MSUF_Header(combatSeparator, "Combat Timer")

    -- In-combat timer checkbox
    local combatTimerCheck = _MSUF_Check("MSUF_Gameplay_CombatTimerCheck", "TOPLEFT", combatHeader, "BOTTOMLEFT", 0, -8, "Enable in-combat timer", "combatTimerCheck", "enableCombatTimer")

    -- Combat Timer anchor dropdown (None / Player / Target / Focus)
    local combatTimerAnchorLabel = _MSUF_Label("GameFontNormal", "LEFT", combatTimerCheck, "RIGHT", 220, 0, "Anchor", "combatTimerAnchorLabel")
    local combatTimerAnchorDD = _MSUF_Dropdown("MSUF_Gameplay_CombatTimerAnchorDropDown", "LEFT", combatTimerAnchorLabel, "RIGHT", 6, -2, 120, "combatTimerAnchorDropdown")

    local function _CombatTimerAnchor_Validate(v) Perfy_Trace(Perfy_GetTime(), "Enter", "_CombatTimerAnchor_Validate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3610:10");
        if v ~= "none" and v ~= "player" and v ~= "target" and v ~= "focus" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_CombatTimerAnchor_Validate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3610:10"); return "none"
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_CombatTimerAnchor_Validate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3610:10"); return v
    end

    local function _CombatTimerAnchor_Text(v) Perfy_Trace(Perfy_GetTime(), "Enter", "_CombatTimerAnchor_Text file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3617:10");
        if v == "player" then Perfy_Trace(Perfy_GetTime(), "Leave", "_CombatTimerAnchor_Text file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3617:10"); return "Player" end
        if v == "target" then Perfy_Trace(Perfy_GetTime(), "Leave", "_CombatTimerAnchor_Text file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3617:10"); return "Target" end
        if v == "focus" then Perfy_Trace(Perfy_GetTime(), "Leave", "_CombatTimerAnchor_Text file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3617:10"); return "Focus" end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_CombatTimerAnchor_Text file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3617:10"); return "None"
    end

    local function _CombatTimerAnchor_Set(v) Perfy_Trace(Perfy_GetTime(), "Enter", "_CombatTimerAnchor_Set file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3624:10");
        local g = MSUF_DB and MSUF_DB.gameplay
        if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "_CombatTimerAnchor_Set file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3624:10"); return end

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
    Perfy_Trace(Perfy_GetTime(), "Leave", "_CombatTimerAnchor_Set file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3624:10"); end

    if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
        UIDropDownMenu_Initialize(combatTimerAnchorDD, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3672:55");
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
                info.func = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3690:28");
                    _CombatTimerAnchor_Set(btn and btn.value)
                    if CloseDropDownMenus then CloseDropDownMenus() end
                Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3690:28"); end
                UIDropDownMenu_AddButton(info, level)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3672:55"); end)
    end

    do
        local g = MSUF_DB and MSUF_DB.gameplay
        local cur = _CombatTimerAnchor_Validate(g and g.combatTimerAnchor)
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(combatTimerAnchorDD, cur) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(combatTimerAnchorDD, _CombatTimerAnchor_Text(cur)) end
    end

    -- Combat Timer size slider
    local combatSlider = _MSUF_Slider("MSUF_Gameplay_CombatFontSizeSlider", "TOPLEFT", combatTimerCheck, "BOTTOMLEFT", 0, -24, 220, 10, 64, 1, "10 px", "64 px", "Timer size", "combatFontSizeSlider", "combatFontSize",
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3708:8"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3708:8", math.floor(v + 0.5)) end,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3709:8"); ApplyFontToCounter() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3709:8"); end,
        false
    )

    -- Combat Timer lock checkbox
    local combatLock = _MSUF_Check("MSUF_Gameplay_LockCombatTimerCheck", "LEFT", combatSlider, "RIGHT", 40, 0, "Lock position", "lockCombatTimerCheck", "lockCombatTimer",
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3715:8");
            ApplyLockState()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3715:8"); end
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

    local function CommitCombatStateTexts() Perfy_Trace(Perfy_GetTime(), "Enter", "CommitCombatStateTexts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3734:10");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "CommitCombatStateTexts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3734:10"); end

    combatStateEnterInput:SetScript("OnEnterPressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3751:54");
        self:ClearFocus()
        CommitCombatStateTexts()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3751:54"); end)
    combatStateEnterInput:SetScript("OnEscapePressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3755:55");
        self:ClearFocus()
        if panel and panel.refresh then
            panel:refresh()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3755:55"); end)
    combatStateEnterInput:SetScript("OnEditFocusLost", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3761:55");
        CommitCombatStateTexts()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3761:55"); end)

    combatStateLeaveInput:SetScript("OnEnterPressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3765:54");
        self:ClearFocus()
        CommitCombatStateTexts()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3765:54"); end)
    combatStateLeaveInput:SetScript("OnEscapePressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3769:55");
        self:ClearFocus()
        if panel and panel.refresh then
            panel:refresh()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3769:55"); end)
    combatStateLeaveInput:SetScript("OnEditFocusLost", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3775:55");
        CommitCombatStateTexts()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3775:55"); end)

    -- Combat Enter/Leave text size slider (shares range with combat timer)
    local combatStateSlider = _MSUF_Slider("MSUF_Gameplay_CombatStateFontSizeSlider", "TOPLEFT", combatStateLeaveInput, "BOTTOMLEFT", 0, -24, 220, 10, 64, 1, "10 px", "64 px", "Text size", "combatStateFontSizeSlider", "combatStateFontSize",
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3781:8"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3781:8", math.floor(v + 0.5)) end,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3782:8"); ApplyFontToCounter() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3782:8"); end,
        false
    )

    -- Combat Enter/Leave lock checkbox (shares lock with combat timer)
    local combatStateLock = _MSUF_Check("MSUF_Gameplay_CombatStateLockCheck", "LEFT", combatStateLeaveInput, "RIGHT", 80, 0, "Lock position", "lockCombatStateCheck", "lockCombatState",
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3788:8");
            ApplyLockState()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3788:8"); end
    )

    -- Duration slider for combat enter/leave text
    local combatStateDurationSlider = _MSUF_Slider("MSUF_Gameplay_CombatStateDurationSlider", "LEFT", combatStateEnterInput, "RIGHT", 80, 0, 160, 0.5, 5.0, 0.5, "Short", "Long", "Duration (s)", "combatStateDurationSlider", "combatStateDuration",
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3795:8"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3795:8", math.floor(v * 10 + 0.5) / 10) end,
        nil,
        false
    )

    -- Reset button next to Duration (restore default 1.5s)
    local combatStateDurationReset = _MSUF_Button("MSUF_Gameplay_CombatStateDurationReset", "LEFT", combatStateSlider, "RIGHT", 40, 0, 60, 20, "Reset", "combatStateDurationResetButton")
    combatStateDurationReset:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3802:50");
        local g = EnsureGameplayDefaults()
        g.combatStateDuration = 1.5
        if panel and panel.combatStateDurationSlider then
            panel.combatStateDurationSlider:SetValue(1.5)
        end
        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3802:50"); end)

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
            function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3842:12");
                if ns and ns.MSUF_RequestGameplayApply then
                    ns.MSUF_RequestGameplayApply()
                end
                if panel and panel.MSUF_UpdateGameplayDisabledStates then
                    panel:MSUF_UpdateGameplayDisabledStates()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3842:12"); end
        )

        local function _RefreshTotemsPreviewButton() Perfy_Trace(Perfy_GetTime(), "Enter", "_RefreshTotemsPreviewButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3852:14");
            if panel and panel.playerTotemsPreviewButton and panel.playerTotemsPreviewButton.SetText then
                local active = (ns and ns.MSUF_PlayerTotems_IsPreviewActive and ns.MSUF_PlayerTotems_IsPreviewActive()) and true or false
                panel.playerTotemsPreviewButton:SetText(active and "Stop preview" or "Preview")
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_RefreshTotemsPreviewButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3852:14"); end

        local totemsShowText = _MSUF_Check("MSUF_Gameplay_PlayerTotemsShowTextCheck", "TOPLEFT", totemsCheck, "BOTTOMLEFT", 0, -8, "Show cooldown text", "playerTotemsShowTextCheck", "playerTotemsShowText",
            function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3860:12");
                if ns and ns.MSUF_RequestGameplayApply then
                    ns.MSUF_RequestGameplayApply()
                end
                if panel and panel.MSUF_UpdateGameplayDisabledStates then
                    panel:MSUF_UpdateGameplayDisabledStates()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3860:12"); end
        )

        local totemsScaleText = _MSUF_Check("MSUF_Gameplay_PlayerTotemsScaleTextCheck", "TOPLEFT", totemsShowText, "BOTTOMLEFT", 0, -8, "Scale text by icon size", "playerTotemsScaleByIconCheck", "playerTotemsScaleTextByIconSize",
            function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3871:12");
                if ns and ns.MSUF_RequestGameplayApply then
                    ns.MSUF_RequestGameplayApply()
                end
                if panel and panel.MSUF_UpdateGameplayDisabledStates then
                    panel:MSUF_UpdateGameplayDisabledStates()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3871:12"); end
        )

        -- Preview button: keep it in the left column under the toggles (cleaner layout).
        -- Preview is Shaman-only and works even when the feature toggle is off (positioning).
        local totemsPreviewBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsPreviewButton", "TOPLEFT", totemsScaleText, "BOTTOMLEFT", 0, -12, 140, 22, "Preview", "playerTotemsPreviewButton")
        totemsPreviewBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3884:46");
            if ns and ns.MSUF_PlayerTotems_TogglePreview then
                ns.MSUF_PlayerTotems_TogglePreview()
            end
            _RefreshTotemsPreviewButton()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3884:46"); end)
        _RefreshTotemsPreviewButton()

        
-- Tip: positioning workflow
local totemsDragHint = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", totemsPreviewBtn, "BOTTOMLEFT", 0, -4, "Tip: Move the preview via mousedrag", "playerTotemsDragHint")
panel.playerTotemsDragHint = totemsDragHint

_totemsLeftBottom = totemsDragHint

	        -- Right column for layout/size controls (keeps the left side clean, avoids clipping)
	        local _totemsRightX = 300

	        local totemsIconSize = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsIconSizeSlider", "TOPLEFT", totemsCheck, "TOPLEFT", _totemsRightX, -2, 240, 8, 64, 1, "Small", "Big", "Icon size", "playerTotemsIconSizeSlider", "playerTotemsIconSize",
            function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3903:12"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3903:12", math.floor((v or 0) + 0.5)) end,
            function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3904:12");
                if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3904:12"); end,
            true
        )

        local totemsSpacing = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsSpacingSlider", "TOPLEFT", totemsIconSize, "BOTTOMLEFT", 0, -18, 240, 0, 20, 1, "Tight", "Wide", "Spacing", "playerTotemsSpacingSlider", "playerTotemsSpacing",
            function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3911:12"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3911:12", math.floor((v or 0) + 0.5)) end,
            function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3912:12"); if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3912:12"); end,
            true
        )

        local totemsOffsetX = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsOffsetXSlider", "TOPLEFT", totemsSpacing, "BOTTOMLEFT", 0, -18, 240, -200, 200, 1, "Left", "Right", "X offset", "playerTotemsOffsetXSlider", "playerTotemsOffsetX",
            function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3917:12"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3917:12", math.floor((v or 0) + 0.5)) end,
            function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3918:12"); if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3918:12"); end,
            true
        )

        local totemsOffsetY = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsOffsetYSlider", "TOPLEFT", totemsOffsetX, "BOTTOMLEFT", 0, -18, 240, -200, 200, 1, "Down", "Up", "Y offset", "playerTotemsOffsetYSlider", "playerTotemsOffsetY",
            function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3923:12"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3923:12", math.floor((v or 0) + 0.5)) end,
            function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3924:12"); if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3924:12"); end,
            true
        )

        local totemsFontSize = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsFontSizeSlider", "TOPLEFT", totemsOffsetY, "BOTTOMLEFT", 0, -18, 240, 8, 64, 1, "Small", "Big", "Font size", "playerTotemsFontSizeSlider", "playerTotemsFontSize",
            function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3929:12"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3929:12", math.floor((v or 0) + 0.5)) end,
            function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3930:12"); if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3930:12"); end,
            true
        )


        local totemsLayoutLabel = _MSUF_Label("GameFontNormal", "TOPLEFT", totemsFontSize, "BOTTOMLEFT", 0, -12, "Layout", "playerTotemsLayoutLabel")
        panel.playerTotemsLayoutLabel = totemsLayoutLabel

        local anchorPoints = {"TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT"}
        local function _NextAnchor(cur) Perfy_Trace(Perfy_GetTime(), "Enter", "_NextAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3939:14");
            if type(cur) ~= "string" then
                return Perfy_Trace_Passthrough("Leave", "_NextAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3939:14", anchorPoints[1])
            end
            for i=1,#anchorPoints do
                if anchorPoints[i] == cur then
                    local j = i + 1
                    if j > #anchorPoints then j = 1 end
                    return Perfy_Trace_Passthrough("Leave", "_NextAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3939:14", anchorPoints[j])
                end
            end
            return Perfy_Trace_Passthrough("Leave", "_NextAnchor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3939:14", anchorPoints[1])
                end

        -- Growth direction dropdown (RIGHT / LEFT / UP / DOWN)
        local growthDD = _MSUF_Dropdown("MSUF_Gameplay_PlayerTotemsGrowthDropDown", "TOPLEFT", totemsLayoutLabel, "BOTTOMLEFT", -16, -10, 110, "playerTotemsGrowthDropdown")

        local function _TotemsGrowth_Validate(v) Perfy_Trace(Perfy_GetTime(), "Enter", "_TotemsGrowth_Validate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3956:14");
            if v ~= "LEFT" and v ~= "RIGHT" and v ~= "UP" and v ~= "DOWN" then
                Perfy_Trace(Perfy_GetTime(), "Leave", "_TotemsGrowth_Validate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3956:14"); return "RIGHT"
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "_TotemsGrowth_Validate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3956:14"); return v
        end

        local function _TotemsGrowth_Set(v) Perfy_Trace(Perfy_GetTime(), "Enter", "_TotemsGrowth_Set file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3963:14");
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "_TotemsGrowth_Set file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3963:14"); return end
            local val = _TotemsGrowth_Validate(v)
            g.playerTotemsGrowthDirection = val

            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(growthDD, val) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(growthDD, val) end

            if panel and panel.refresh then panel:refresh() end
            if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_TotemsGrowth_Set file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3963:14"); end

        if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
            UIDropDownMenu_Initialize(growthDD, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3977:48");
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
                    info.func = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3995:32");
                        _TotemsGrowth_Set(btn and btn.value)
                    Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3995:32"); end
                    UIDropDownMenu_AddButton(info, level)
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:3977:48"); end)
        end

        -- Initial label/selection (kept in sync by panel.refresh)
        do
            local g = MSUF_DB and MSUF_DB.gameplay
            local cur = _TotemsGrowth_Validate(g and g.playerTotemsGrowthDirection)
            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(growthDD, cur) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(growthDD, cur) end
        end


	        local anchorFromBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsAnchorFromBtn", "TOPLEFT", growthDD, "TOPRIGHT", 8, -4, 122, 20, "From: TOPLEFT", "playerTotemsAnchorFromButton", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4012:185");
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4012:185"); return end
            g.playerTotemsAnchorFrom = _NextAnchor(g.playerTotemsAnchorFrom)
            if panel and panel.refresh then panel:refresh() end
            if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4012:185"); end)
        panel.playerTotemsAnchorFromButton = anchorFromBtn

	        local anchorToBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsAnchorToBtn", "TOPLEFT", growthDD, "BOTTOMLEFT", 16, -6, 240, 20, "To: BOTTOMLEFT", "playerTotemsAnchorToButton", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4021:183");
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4021:183"); return end
            g.playerTotemsAnchorTo = _NextAnchor(g.playerTotemsAnchorTo)
            if panel and panel.refresh then panel:refresh() end
            if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4021:183"); end)
        panel.playerTotemsAnchorToButton = anchorToBtn

	        local resetTotemsBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsResetBtn", "TOPLEFT", anchorToBtn, "BOTTOMLEFT", 0, -6, 240, 20, "Reset Totem tracker layout", "playerTotemsResetButton", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4030:194");
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4030:194"); return end
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4030:194"); end)
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
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4090:8"); if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4090:8"); end
    )

    -- Combat crosshair: melee range coloring (uses the shared melee spell selection)
    local crosshairRangeColorCheck = _MSUF_Check("MSUF_Gameplay_CrosshairRangeColorCheck", "TOPLEFT", combatCrosshairCheck, "BOTTOMLEFT", 0, -8, "Crosshair: color by melee range to target (green=in range, red=out)", "crosshairRangeColorCheck", "enableCombatCrosshairMeleeRangeColor",
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4095:8"); if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4095:8"); end
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

    local function ClampInt(v, lo, hi) Perfy_Trace(Perfy_GetTime(), "Enter", "ClampInt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4176:10");
        v = tonumber(v) or lo
        v = math.floor(v + 0.5)
        if v < lo then v = lo end
        if v > hi then v = hi end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ClampInt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4176:10"); return v
    end

    local function UpdateCrosshairPreview() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateCrosshairPreview file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4184:10");
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
            crosshairPreview:SetScript("OnUpdate", function(self, elapsed) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4249:51");
                self._elapsed = (self._elapsed or 0) + (elapsed or 0)
                if self._elapsed >= 0.85 then
                    self._elapsed = 0
                    self._phase = (self._phase == 1) and 0 or 1
                    UpdateCrosshairPreview()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4249:51"); end)
        else
            crosshairPreview:SetScript("OnUpdate", nil)
            crosshairPreview._elapsed = 0
            crosshairPreview._phase = 0
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateCrosshairPreview file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4184:10"); end

    panel.MSUF_UpdateCrosshairPreview = UpdateCrosshairPreview

    -- Combat crosshair thickness slider
    local crosshairThicknessLabel = _MSUF_Label("GameFontHighlight", "TOPLEFT", meleeSelected or (meleeSharedWarn or crosshairRangeWarn), "BOTTOMLEFT", 0, -24, "Crosshair thickness", "crosshairThicknessLabel")

    local crosshairThicknessSlider = _MSUF_Slider("MSUF_Gameplay_CrosshairThicknessSlider", "TOPLEFT", crosshairThicknessLabel, "BOTTOMLEFT", 0, -12, 240, 1, 10, 1, "1 px", "10 px", "2 px", "crosshairThicknessSlider", "crosshairThickness",
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4270:8"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4270:8", math.floor(v + 0.5)) end,
        function(self, g, v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4271:8");
            _G[self:GetName() .. "Text"]:SetText(string.format("%d px", v))
            if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4271:8"); end,
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
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4288:8");
            v = math.floor(v + 0.5)
            if v < 20 then v = 20 elseif v > 80 then v = 80 end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4288:8"); return v
        end,
        function(self, g, v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4293:8");
            _G[self:GetName() .. "Text"]:SetText(string.format("%d px", v))
            if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4293:8"); end,
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
    local function _MSUF_RememberTextColor(fs) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_RememberTextColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4317:10");
        if not fs or fs.__msufOrigColor then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_RememberTextColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4317:10"); return end
        local r, g, b, a = fs:GetTextColor()

        -- Important: many Blizzard templates use a yellow default font color (GameFontNormal).
        -- For Gameplay toggles we want the "enabled" baseline to be WHITE (like the rest of MSUF),
        -- otherwise the first state refresh after a click can "lock in" yellow and spread across toggles.
        if r and g and b and (r > 0.95) and (g > 0.70) and (g < 0.95) and (b < 0.30) then
            fs.__msufOrigColor = { 1, 1, 1, a or 1 }
        else
            fs.__msufOrigColor = { r or 1, g or 1, b or 1, a or 1 }
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_RememberTextColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4317:10"); end

    local function _MSUF_SetFontStringEnabled(fs, enabled, dimWhenOff) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SetFontStringEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4331:10");
        if not fs then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetFontStringEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4331:10"); return end
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetFontStringEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4331:10"); end

    local function _MSUF_SetCheckStyle(cb, forceEnabled) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SetCheckStyle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4347:10");
        if not cb then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetCheckStyle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4347:10"); return end
        if forceEnabled then
            cb:Enable()
        end

        local fs = cb.Text
        if not fs then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetCheckStyle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4347:10"); return end
        _MSUF_RememberTextColor(fs)

        if not cb:IsEnabled() then
            fs:SetTextColor(0.45, 0.45, 0.45, 0.9)
            Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetCheckStyle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4347:10"); return
        end

        -- Unchecked toggles are intentionally greyed (like Main menu)
        if cb:GetChecked() then
            local c = fs.__msufOrigColor
            fs:SetTextColor(c[1], c[2], c[3], c[4])
        else
            fs:SetTextColor(0.60, 0.60, 0.60, 0.95)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetCheckStyle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4347:10"); end

    local function _MSUF_SetCheckEnabled(cb, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SetCheckEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4371:10");
        if not cb then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetCheckEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4371:10"); return end
        if enabled then
            cb:Enable()
        else
            cb:Disable()
        end
        _MSUF_SetCheckStyle(cb)
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetCheckEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4371:10"); end

    local function _MSUF_SetSliderEnabled(sl, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SetSliderEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4381:10");
        if not sl then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetSliderEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4381:10"); return end
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetSliderEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4381:10"); end

    local function _MSUF_SetButtonEnabled(btn, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SetButtonEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4398:10");
        if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetButtonEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4398:10"); return end
        btn:SetEnabled(enabled and true or false)
        btn:SetAlpha(enabled and 1 or 0.6)
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetButtonEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4398:10"); end

local function _MSUF_SetDropdownEnabled(dd, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SetDropdownEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4404:6");
    if not dd then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetDropdownEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4404:6"); return end
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
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetDropdownEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4404:6"); end


    local function _MSUF_SetEditBoxEnabled(eb, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SetEditBoxEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4424:10");
        if not eb then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetEditBoxEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4424:10"); return end
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetEditBoxEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4424:10"); end

    function panel:MSUF_UpdateGameplayDisabledStates() Perfy_Trace(Perfy_GetTime(), "Enter", "panel:MSUF_UpdateGameplayDisabledStates file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4447:4");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "panel:MSUF_UpdateGameplayDisabledStates file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4447:4"); end

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

    }

    local function _MSUF_ResetGameplayToDefaults() Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_ResetGameplayToDefaults file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4615:10");
        local g = EnsureGameplayDefaults()
        for i = 1, #_MSUF_GAMEPLAY_DEFAULT_KEYS do
            g[_MSUF_GAMEPLAY_DEFAULT_KEYS[i]] = nil
        end
        return Perfy_Trace_Passthrough("Leave", "_MSUF_ResetGameplayToDefaults file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4615:10", EnsureGameplayDefaults())
    end

    local function _MSUF_Clamp(v, lo, hi) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4623:10");
        if v == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4623:10"); return lo end
        if v < lo then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4623:10"); return lo end
        if v > hi then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4623:10"); return hi end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4623:10"); return v
    end

    panel.refresh = function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "panel.refresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4630:20");
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

        local function SetCheck(field, key, notFalse) Perfy_Trace(Perfy_GetTime(), "Enter", "SetCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4657:14");
            local cb = self[field]
            if not cb then Perfy_Trace(Perfy_GetTime(), "Leave", "SetCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4657:14"); return end
            local v = notFalse and (g[key] ~= false) or (g[key] and true or false)
            cb:SetChecked(v)
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4657:14"); end

        local function SetSlider(field, key, default) Perfy_Trace(Perfy_GetTime(), "Enter", "SetSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4664:14");
            local sl = self[field]
            if not sl then Perfy_Trace(Perfy_GetTime(), "Leave", "SetSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4664:14"); return end
            sl:SetValue(tonumber(g[key]) or default or 0)
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4664:14"); end

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
    Perfy_Trace(Perfy_GetTime(), "Leave", "panel.refresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4630:20"); end



-- Live-sync: allow the Totem preview frame to drag-update X/Y without spamming Apply().
function panel:MSUF_SyncTotemOffsetSliders() Perfy_Trace(Perfy_GetTime(), "Enter", "panel:MSUF_SyncTotemOffsetSliders file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4794:0");
    if not self.playerTotemsOffsetXSlider or not self.playerTotemsOffsetYSlider then
        Perfy_Trace(Perfy_GetTime(), "Leave", "panel:MSUF_SyncTotemOffsetSliders file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4794:0"); return
    end
    local g = EnsureGameplayDefaults()
    self._msufSuppressSliderChanges = true
    self.playerTotemsOffsetXSlider:SetValue(tonumber(g.playerTotemsOffsetX) or 0)
    self.playerTotemsOffsetYSlider:SetValue(tonumber(g.playerTotemsOffsetY) or -6)
    self._msufSuppressSliderChanges = false
Perfy_Trace(Perfy_GetTime(), "Leave", "panel:MSUF_SyncTotemOffsetSliders file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4794:0"); end

    -- Most controls apply immediately, but "Okay" is still called by the Settings/Interface panel system.
    -- We use it as a safe "finalize" hook.
    panel.okay = function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "panel.okay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4807:17");
        if self.meleeSpellInput and self.meleeSpellInput.HasFocus and self.meleeSpellInput:HasFocus() then
            self.meleeSpellInput:ClearFocus()
        end

        ns.MSUF_RequestGameplayApply()

        if ns and ns.MSUF_RequestCooldownIconsSync then
            ns.MSUF_RequestCooldownIconsSync()
        elseif MSUF_ApplyCooldownIconMode then
            MSUF_ApplyCooldownIconMode()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "panel.okay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4807:17"); end

    panel.default = function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "panel.default file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4821:20");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "panel.default file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4821:20"); end

    
    ------------------------------------------------------
    -- Dynamic content height
    ------------------------------------------------------
    local function UpdateContentHeight() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateContentHeight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4840:10");
        local minHeight = 400
        if not lastControl then
            content:SetHeight(minHeight)
            Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateContentHeight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4840:10"); return
        end

        local bottom = lastControl:GetBottom()
        local top    = content:GetTop()
        if not bottom or not top then
            content:SetHeight(minHeight)
            Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateContentHeight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4840:10"); return
        end

        local padding = 40
        local height  = top - bottom + padding
        if height < minHeight then
            height = minHeight
        end
        content:SetHeight(height)
    Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateContentHeight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4840:10"); end

    panel:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4862:30");
        if _G.MSUF_StyleAllToggles then _G.MSUF_StyleAllToggles(panel) end
        if panel.refresh then
            panel:refresh()
        end
        UpdateContentHeight()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4862:30"); end)

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
    Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_RegisterGameplayOptions_Full file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:2966:0"); return panel
end


-- Lightweight wrapper: register the category at login, but build the heavy UI only when opened.
function ns.MSUF_RegisterGameplayOptions(parentCategory) Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_RegisterGameplayOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4896:0");
    if not Settings or not Settings.RegisterCanvasLayoutSubcategory or not parentCategory then
        -- Fallback: if Settings API isn't available, just build immediately.
        return Perfy_Trace_Passthrough("Leave", "ns.MSUF_RegisterGameplayOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4896:0", ns.MSUF_RegisterGameplayOptions_Full(parentCategory))
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_RegisterGameplayOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4896:0"); return panel
    end

    -- First open builds the full panel. Build synchronously in OnShow so the panel is ready on the first click.

    if not panel.__MSUF_LazyBuildHooked then

        panel.__MSUF_LazyBuildHooked = true

    

        panel:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4935:35");

            if panel.__MSUF_GameplayBuilt or panel.__MSUF_GameplayBuilding then

                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4935:35"); return

            end

            panel.__MSUF_GameplayBuilding = true

    

            -- Build immediately (no C_Timer.After(0)): avoids "needs second click" issues.

            ns.MSUF_RegisterGameplayOptions_Full(parentCategory)

    

            panel.__MSUF_GameplayBuilding = nil

        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4935:35"); end)

    end

    

    Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_RegisterGameplayOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4896:0"); return panel

    end


------------------------------------------------------
-- Auto-apply Gameplay features on load
-- Fixes: after /reload or relog, Combat Enter/Leave text (and other Gameplay
-- features) could be "enabled" in the UI but not actually active until the
-- checkbox was toggled in the Gameplay menu.
------------------------------------------------------
do
    local didApply = false

    local function AutoApplyOnce() Perfy_Trace(Perfy_GetTime(), "Enter", "AutoApplyOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4975:10");
        if didApply then Perfy_Trace(Perfy_GetTime(), "Leave", "AutoApplyOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4975:10"); return end
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "AutoApplyOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:4975:10"); end

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
    f:SetScript("OnEvent", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:5005:27");
        AutoApplyOnce()
        f:UnregisterAllEvents()
        f:SetScript("OnEvent", nil)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua:5005:27"); end)
end

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Gameplay.lua");