--- MSUF_Feature_GameplayConfig.lua
--- DB/default/font/color helpers for gameplay features. Cold/warm path only.
local _, MSUF = ...
MSUF = MSUF or {}

local type, rawget, tonumber = type, rawget, tonumber
local math_floor = math.floor
local LibStub = LibStub
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local ResolveFontPath = _G.MSUF_ResolveFontPath or function(path) return path end
local GameplayHelpers = MSUF.Gameplay or {}
local _MSUF_Clamp = GameplayHelpers.Clamp or _G._MSUF_Clamp

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF) == "table" and type(MSUF.Translate) == "function" then
        return MSUF.Translate(text)
    end
    local locale = (type(MSUF) == "table" and MSUF.L) or _G.MSUF_L
    if type(locale) == "table" then
        local translated = rawget(locale, text)
        if translated ~= nil then return translated end
    end
    return text
end

local L_GAMEPLAY_COLORS_TIP
local function RefreshLocaleText()
    L_GAMEPLAY_COLORS_TIP = Tr("Tip: Gameplay colors are in Colors > Gameplay")
end
RefreshLocaleText()
if type(MSUF.RegisterLocaleCallback) == "function" then
    MSUF.RegisterLocaleCallback("MSUF_GameplayConfig", RefreshLocaleText)
end
---
--- SavedVars helper (own sub-table under MSUF_DB)
---
local gameplayDBCache

local function EnsureGameplayDefaults()
    if not MSUF_DB then
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
    --- In-combat timer toggle
    if g.enableCombatTimer == nil then
        g.enableCombatTimer = false
    end
    --- Absolute pixel size override for the combat timer text.
    if g.combatFontSize == nil or g.combatFontSize <= 0 then
        g.combatFontSize = 24
    end
    if g.combatFontSize < 10 then
        g.combatFontSize = 10
    elseif g.combatFontSize > 64 then
        g.combatFontSize = 64
    end
    --- Lock state for combat timer (shares the same frame, but has its own toggle)
    if g.lockCombatTimer == nil then
        g.lockCombatTimer = false
    end
    --- When enabled, the combat timer frame never steals clicks (recommended).
    --- When disabled, the timer can be dragged normally while unlocked (no ALT needed).
    if g.combatTimerClickThrough == nil then
        g.combatTimerClickThrough = true
    end

    --- Anchor target for the combat timer (none/player/target/focus)
    if g.combatTimerAnchor == nil then
        g.combatTimerAnchor = "none"
    end
    --- Combat timer text color (configured from the Colors menu)
    if type(g.combatTimerColor) ~= "table" then
        g.combatTimerColor = { 1, 1, 1 } --- default white
    end

    --- Independent position and lock for combat enter/leave text
    if g.combatStateOffsetX == nil then
        g.combatStateOffsetX = 0
    end
    if g.combatStateOffsetY == nil then
        g.combatStateOffsetY = 80
    end
    if g.lockCombatState == nil then
        g.lockCombatState = false
    end

    --- Absolute pixel size override for combat enter/leave text.
    if g.combatStateFontSize == nil or g.combatStateFontSize <= 0 then
        g.combatStateFontSize = 24
    end
    if g.combatStateFontSize < 10 then
        g.combatStateFontSize = 10
    elseif g.combatStateFontSize > 64 then
        g.combatStateFontSize = 64
    end

    --- Duration that combat enter/leave text stays visible (in seconds)
    if g.combatStateDuration == nil then
        g.combatStateDuration = 1.5
    end

    if g.enableCombatStateText == nil then
        g.enableCombatStateText = false
    end

    --- Customizable combat enter/leave strings (shown briefly on regen events)
    if g.combatStateEnterText == nil then
        g.combatStateEnterText = "+Combat"
    end
    if g.combatStateLeaveText == nil then
        g.combatStateLeaveText = "-Combat"
    end

--- Combat state text colors (configured from the Colors menu)
--- Stored as {r,g,b}. Defaults match the legacy hardcoded colors:
--- Enter = white, Leave = light gray.
if g.combatStateEnterColor == nil then
    g.combatStateEnterColor = { 1, 1, 1 }
end
if g.combatStateLeaveColor == nil then
    g.combatStateLeaveColor = { 0.7, 0.7, 0.7 }
end
if g.combatStateColorSync == nil then
    g.combatStateColorSync = false
end

    --- Rogue "The First Dance" timer (6s after leaving combat)
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

    --- Green combat crosshair under player while in combat
    if g.enableCombatCrosshair == nil then
        g.enableCombatCrosshair = false
    end

    --- Combat crosshair thickness (line width in pixels)
    if g.crosshairThickness == nil then
        g.crosshairThickness = 2
    end

    --- Combat crosshair size (overall crosshair size in pixels)
    if g.crosshairSize == nil then
        g.crosshairSize = 40
    end

    --- Combat crosshair: color by melee range (uses the shared melee spell selection)
    --- Green = in melee range, Red = out of melee range
    if g.enableCombatCrosshairMeleeRangeColor == nil then
        g.enableCombatCrosshairMeleeRangeColor = false
    end
    --- Combat crosshair range colors
    if type(g.crosshairInRangeColor) ~= "table" then
        g.crosshairInRangeColor = { 0, 1, 0 } --- default green
    end
    if type(g.crosshairOutRangeColor) ~= "table" then
        g.crosshairOutRangeColor = { 1, 0, 0 } --- default red
    end
    --- Per-class / per-spec storage for the melee range spell
    if g.meleeSpellPerClass == nil then g.meleeSpellPerClass = false end
    if g.meleeSpellPerSpec == nil then g.meleeSpellPerSpec = false end
    if type(g.nameplateMeleeSpellIDByClass) ~= "table" then g.nameplateMeleeSpellIDByClass = {} end
    if type(g.nameplateMeleeSpellIDBySpec) ~= "table" then g.nameplateMeleeSpellIDBySpec = {} end
    --- Blizzard TotemFrame re-anchor. Used by Shaman totems and Monk statues.
    --- Default ON for supported classes on first run; otherwise default OFF.
    if g.enablePlayerTotems == nil then
        local hasTotemFrame = false
        if UnitClass then
            local _, cls = UnitClass("player")
            hasTotemFrame = (cls == "SHAMAN" or cls == "MONK")
        end
        g.enablePlayerTotems = hasTotemFrame and true or false
    end
    if g.playerTotemsIconSize == nil or g.playerTotemsIconSize <= 0 then
        g.playerTotemsIconSize = 24
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

    --- Retire settings from the removed custom scanner. Blizzard's TotemFrame owns
    --- text, spacing, duration, and colors now.
    g.playerTotemsShowText = nil
    g.playerTotemsScaleTextByIconSize = nil
    g.playerTotemsSpacing = nil
    g.playerTotemsGrowthDirection = nil
    g.playerTotemsFontSize = nil
    g.playerTotemsTextColor = nil

    --- One-time tip popup flag
    if g.shownGameplayColorsTip == nil then
        g.shownGameplayColorsTip = false
    end

    gameplayDBCache = g
    return g
end

--- Hotpath helper: avoid calling EnsureGameplayDefaults() every tick.
--- The gameplay DB table is stable; this cache is refreshed whenever EnsureGameplayDefaults() runs.
local function GetGameplayDBFast()
    if type(gameplayDBCache) == "table" then
        return gameplayDBCache
    end
    return EnsureGameplayDefaults()
end

---
--- One-time tip popup: gameplay colors live in Colors ? Gameplay
---
do
    local POPUP_KEY = "MSUF_GAMEPLAY_COLORS_TIP"

    local function EnsureDialog()
        if not _G.StaticPopupDialogs then
            return false
        end
        if not _G.StaticPopupDialogs[POPUP_KEY] then
            _G.StaticPopupDialogs[POPUP_KEY] = {
                --- ASCII only (avoid missing glyph boxes in some fonts)
                text = L_GAMEPLAY_COLORS_TIP,
                button1 = OKAY,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
        end
        return true
    end

    function MSUF.MSUF_MaybeShowGameplayColorsTip()
        local g = EnsureGameplayDefaults()
        if g and g.shownGameplayColorsTip then return end
        if EnsureDialog() and _G.StaticPopup_Show then
            --- Mark as shown before showing so we never spam, even if the dialog is dismissed instantly.
            if g then
                g.shownGameplayColorsTip = true
            end
            _G.StaticPopup_Show(POPUP_KEY)
        end
    end
end

---
--- Font helper: reuse global MSUF text style
---
local function GetGameplayFontSettings(kind)
    local gGameplay = EnsureGameplayDefaults()

    local general = (MSUF_DB and MSUF_DB.general) or {}

    --- FONT PATH
    local fontPath

    local fontKey = general.fontKey
    local pathForKey = _G.MSUF_GetFontPathForKey or (MSUF and MSUF.MSUF_GetFontPathForKey)
    if type(pathForKey) == "function" and fontKey and fontKey ~= "" then
        fontPath = pathForKey(fontKey)
    end
    if (not fontPath or fontPath == "") and LSM and fontKey and fontKey ~= "" then
        local raw = _G.MSUF_GetRawLSMFontPath
        local fetched = type(raw) == "function" and raw(LSM, fontKey) or nil
        if not fetched and type(LSM.HashTable) == "function" then
            local fonts = LSM:HashTable("font")
            fetched = fonts and fonts[fontKey]
        end
        if fetched then
            fontPath = ResolveFontPath(fetched, general.fontSize or 14, "")
        end
    end

    if not fontPath or fontPath == "" then
        fontPath = ResolveFontPath("Fonts/FRIZQT__.TTF", general.fontSize or 14, "")
    end

    --- FONT FLAGS (outline)
    local flags
    if general.noOutline then
        flags = ""
    elseif general.boldText then
        flags = "THICKOUTLINE"
    else
        flags = "OUTLINE"
    end

    --- FONT COLOR (reuse MSUF_FONT_COLORS global)
    local colorKey = (general.fontColor or "white"):lower()
    local colorTbl = (MSUF_FONT_COLORS and MSUF_FONT_COLORS[colorKey]) or (MSUF_FONT_COLORS and MSUF_FONT_COLORS.white) or {1, 1, 1}
    local fr, fg, fb = colorTbl[1], colorTbl[2], colorTbl[3]

    --- BASE SIZE + optional gameplay override
    local baseSize  = general.fontSize or 14
    local override

    if kind == "timer" then
        --- In-combat timer text
        override = gGameplay.combatFontSize or 0
    elseif kind == "state" then
        --- Combat enter/leave text (falls back to combat timer size if 0)
        override = gGameplay.combatStateFontSize
        if not override or override == 0 then
            override = gGameplay.combatFontSize or 0
        end
    else
        --- Other gameplay texts
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

---
--- Combat state text colors (Enter/Leave)
---
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
    --- Defaults match the legacy hardcoded values.
    local er, eg, eb = _MSUF_NormalizeRGB(g and g.combatStateEnterColor, 1, 1, 1)
    local lr, lg, lb = _MSUF_NormalizeRGB(g and g.combatStateLeaveColor, 0.7, 0.7, 0.7)

    if g and g.combatStateColorSync then
        lr, lg, lb = er, eg, eb
    end
    return er, eg, eb, lr, lg, lb
end


MSUF.MSUF_EnsureGameplayDefaults = EnsureGameplayDefaults
MSUF.MSUF_GetGameplayDBFast = GetGameplayDBFast
MSUF.MSUF_GetGameplayFontSettings = GetGameplayFontSettings
MSUF.MSUF_NormalizeRGB = _MSUF_NormalizeRGB
MSUF.MSUF_GetCombatStateColors = MSUF_GetCombatStateColors
