local _, MSUF = ...
MSUF = MSUF or {}

-- Gameplay configuration defaults.
-- Initializes and clamps DB fields for optional gameplay features. Runtime modules consume
-- these values later; this file should not create frames or register gameplay events.
local type, rawget, tonumber = type, rawget, tonumber
local LibStub = LibStub
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local ResolveFontPath = _G.MSUF_ResolveFontPath or function(path) return path end

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF.Translate) == "function" then return MSUF.Translate(text) end
    local locale = MSUF.L or _G.MSUF_L
    local translated = type(locale) == "table" and rawget(locale, text)
    return translated or text
end

local L_GAMEPLAY_COLORS_TIP
local function RefreshLocaleText()
    L_GAMEPLAY_COLORS_TIP = Tr("Tip: Gameplay colors are in Colors > Gameplay")
end
RefreshLocaleText()
if type(MSUF.RegisterLocaleCallback) == "function" then
    MSUF.RegisterLocaleCallback("MSUF_GameplayConfig", RefreshLocaleText)
end

local function Default(g, key, value)
    if g[key] == nil then g[key] = value end
end

local function DefaultText(g, key, value)
    if type(g[key]) ~= "string" or g[key] == "" then g[key] = value end
end

local function DefaultRGB(g, key, r, gCol, b)
    if type(g[key]) ~= "table" then g[key] = { r, gCol, b } end
end

local function ClampPositive(g, key, default, minValue, maxValue)
    local v = tonumber(g[key])
    if not v or v <= 0 then v = default end
    if v < minValue then v = minValue elseif v > maxValue then v = maxValue end
    g[key] = v
end
local gameplayDBCache

local function EnsureGameplayDefaults()
    -- Defaults are intentionally centralized so Menu2, assistant registry, and runtime all
    -- agree on missing-field behavior after profile import or version migration.
    if type(MSUF_DB) ~= "table" or type(_G.MSUF_ActiveProfile) ~= "string" then
        if type(_G.MSUF_InitProfiles) == "function" then
            _G.MSUF_InitProfiles()
        elseif type(_G.MSUF_EnsureDB) == "function" then
            _G.MSUF_EnsureDB()
        end
    end
    if type(MSUF_DB) ~= "table" then
        MSUF_DB = {}
    end
    if type(MSUF_DB.gameplay) ~= "table" then
        MSUF_DB.gameplay = {}
    end

    local g = MSUF_DB.gameplay

    Default(g, "nameplateMeleeSpellID", 0)
    Default(g, "combatOffsetX", 0)
    Default(g, "combatOffsetY", -200)
    Default(g, "enableCombatTimer", false)
    Default(g, "lockCombatTimer", false)
    Default(g, "combatTimerClickThrough", true)
    Default(g, "combatTimerAnchor", "none")
    DefaultRGB(g, "combatTimerColor", 1, 1, 1)
    ClampPositive(g, "combatFontSize", 24, 10, 64)

    Default(g, "combatStateOffsetX", 0)
    Default(g, "combatStateOffsetY", 80)
    Default(g, "lockCombatState", false)
    Default(g, "combatStateDuration", 1.5)
    Default(g, "enableCombatStateText", false)
    Default(g, "combatStateColorSync", false)
    Default(g, "combatStateEnterText", "+Combat")
    Default(g, "combatStateLeaveText", "-Combat")
    if g.combatStateEnterColor == nil then g.combatStateEnterColor = { 1, 1, 1 } end
    if g.combatStateLeaveColor == nil then g.combatStateLeaveColor = { 0.7, 0.7, 0.7 } end
    ClampPositive(g, "combatStateFontSize", 24, 10, 64)

    Default(g, "enableCombatCrosshair", false)
    Default(g, "crosshairThickness", 2)
    Default(g, "crosshairSize", 40)
    Default(g, "enableCombatCrosshairMeleeRangeColor", false)
    DefaultRGB(g, "crosshairInRangeColor", 0, 1, 0)
    DefaultRGB(g, "crosshairOutRangeColor", 1, 0, 0)
    Default(g, "meleeSpellPerClass", false)
    Default(g, "meleeSpellPerSpec", false)
    if type(g.nameplateMeleeSpellIDByClass) ~= "table" then g.nameplateMeleeSpellIDByClass = {} end
    if type(g.nameplateMeleeSpellIDBySpec) ~= "table" then g.nameplateMeleeSpellIDBySpec = {} end
    -- Blizzard's TotemFrame is class-agnostic and parented to PlayerFrame, which MSUF hides, so
    -- this helper is what makes an occupied totem slot visible at all. Seeded on for every class
    -- instead of just Shaman/Monk; profiles that already stored a value keep it.
    Default(g, "enablePlayerTotems", true)
    if g.playerTotemsIconSize == nil or g.playerTotemsIconSize <= 0 then g.playerTotemsIconSize = 24 end
    Default(g, "playerTotemsOffsetX", 0)
    Default(g, "playerTotemsOffsetY", -6)
    DefaultText(g, "playerTotemsAnchorFrom", "TOPLEFT")
    DefaultText(g, "playerTotemsAnchorTo", "BOTTOMLEFT")

    g.playerTotemsShowText = nil
    g.playerTotemsScaleTextByIconSize = nil
    g.playerTotemsSpacing = nil
    g.playerTotemsGrowthDirection = nil
    g.playerTotemsFontSize = nil
    g.playerTotemsTextColor = nil

    Default(g, "shownGameplayColorsTip", false)

    gameplayDBCache = g
    return g
end

local function GetGameplayDBFast()
    if type(gameplayDBCache) == "table" then
        return gameplayDBCache
    end
    return EnsureGameplayDefaults()
end

do
    local POPUP_KEY = "MSUF_GAMEPLAY_COLORS_TIP"

    local function EnsureDialog()
        if not _G.StaticPopupDialogs then return false end
        if not _G.StaticPopupDialogs[POPUP_KEY] then
            _G.StaticPopupDialogs[POPUP_KEY] = {
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
            if g then g.shownGameplayColorsTip = true end
            _G.StaticPopup_Show(POPUP_KEY)
        end
    end
end

local function GetGameplayFontSettings(kind)
    local gGameplay = EnsureGameplayDefaults()

    local general = (MSUF_DB and MSUF_DB.general) or {}

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

    local flags
    if general.noOutline then
        flags = ""
    elseif general.boldText then
        flags = "THICKOUTLINE"
    else
        flags = "OUTLINE"
    end
    if general.fontSlug then
        flags = flags == "" and "SLUG" or "OUTLINE,SLUG"
    elseif general.fontMonochrome then
        flags = flags ~= "" and (flags .. ",MONOCHROME") or "MONOCHROME"
    end

    local colorKey = (general.fontColor or "white"):lower()
    local colorTbl = (MSUF_FONT_COLORS and MSUF_FONT_COLORS[colorKey]) or (MSUF_FONT_COLORS and MSUF_FONT_COLORS.white) or {1, 1, 1}
    local fr, fg, fb = colorTbl[1], colorTbl[2], colorTbl[3]

    local baseSize  = general.fontSize or 14
    local override

    if kind == "timer" then
        override = gGameplay.combatFontSize or 0
    elseif kind == "state" then
        override = gGameplay.combatStateFontSize
        if not override or override == 0 then
            override = gGameplay.combatFontSize or 0
        end
    else
        override = gGameplay.fontSize or 0
    end
    local effSize
    if override > 0 then
        effSize = override
    else
        effSize = math.floor(baseSize * 1.6 + 0.5)
    end

    local useShadow = not (general and general.textBackdrop == false)
        and not tostring(flags or ""):upper():find("SLUG", 1, true)

    return fontPath, flags, fr, fg, fb, effSize, useShadow
end

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
