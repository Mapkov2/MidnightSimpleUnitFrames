-- MidnightSimpleUnitFrames
local addonName, ns = ...
ns = ns or {}

-- Simple local cache for speed
local tonumber, tostring, ipairs, type = tonumber, tostring, ipairs, type
-- Settings-Kategorie + Minimap-Button Handle

-- Shared constants / tunables
local MSUF_MAX_BOSS_FRAMES = 5          -- how many boss frames MSUF creates/handles

-- Reusable texture path (WHITE8x8) so we don't repeat the literal everywhere
local MSUF_TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"

-- Frequently used API functions (localized for tiny perf wins)
local GetTime               = GetTime
local UnitHealth            = UnitHealth
local UnitHealthMax         = UnitHealthMax
local UnitPower             = UnitPower
local UnitPowerMax          = UnitPowerMax
local UnitName              = UnitName
local UnitClass             = UnitClass
local UnitIsDeadOrGhost     = UnitIsDeadOrGhost
local UnitIsPlayer          = UnitIsPlayer
local UnitIsGroupLeader     = UnitIsGroupLeader
local UnitExists            = UnitExists
local UnitHealthPercent     = UnitHealthPercent
local AbbreviateLargeNumbers = AbbreviateLargeNumbers
local InCombatLockdown      = InCombatLockdown

local MSUF_SettingsCategory -- wird in CreateOptionsPanel gesetzt
local MSUF_MinimapButton    -- wird einmalig erzeugt
-- UI / frame helpers
local CreateFrame = CreateFrame
local UIParent    = UIParent

-- Math / string helpers
local floor  = math.floor
local max    = math.max
local min    = math.min
local format = string.format

-- Table helpers
local tinsert = table.insert
local pairs   = pairs   -- wir nutzen pairs ziemlich oft, bisher als Global


------------------------------------------------------
-- LIGHTWEIGHT INTERNAL PROFILER (optional)
------------------------------------------------------
local MSUF_PROFILE = false
local MSUF_ProfileData = {}

local function MSUF_ProfileEnabled()
    return MSUF_PROFILE and type(debugprofilestop) == "function"
end

function ns.MSUF_ProfileSetEnabled(flag)
    MSUF_PROFILE = not not flag
    if not MSUF_PROFILE then
        for _, entry in pairs(MSUF_ProfileData) do
            entry.t0 = nil
        end
    end
end

local function MSUF_ProfileStart(key)
    if not MSUF_ProfileEnabled() then
        return
    end
    local entry = MSUF_ProfileData[key]
    if not entry then
        entry = { time = 0, calls = 0 }
        MSUF_ProfileData[key] = entry
    end
    entry.t0 = debugprofilestop()
end

local function MSUF_ProfileStop(key)
    if not MSUF_ProfileEnabled() then
        return
    end
    local entry = MSUF_ProfileData[key]
    if not entry or not entry.t0 then
        return
    end

    local now = debugprofilestop()
    if not now then
        entry.t0 = nil
        return
    end

    local dt = now - entry.t0
    if dt < 0 then
        dt = 0
    end

    entry.time  = entry.time + dt
    entry.calls = entry.calls + 1
    entry.t0    = nil
end

SLASH_MSUFPROFILE1 = "/msufprofile"
SlashCmdList["MSUFPROFILE"] = function(msg)
    local cmd = msg and msg:lower():match("^%s*(%S*)") or ""

    if cmd == "on" or cmd == "enable" then
        ns.MSUF_ProfileSetEnabled(true)
        MSUF_ProfileData = {}
        print("|cffffd700MSUF:|r Profiler |cff00ff00ENABLED|r. Do some combat, then /msufprofile.")
        return
    elseif cmd == "off" or cmd == "disable" then
        ns.MSUF_ProfileSetEnabled(false)
        print("|cffffd700MSUF:|r Profiler |cffff0000DISABLED|r.")
        return
    elseif cmd == "reset" then
        MSUF_ProfileData = {}
        print("|cffffd700MSUF:|r Profile data reset.")
        return
    end

    if not MSUF_ProfileEnabled() or not next(MSUF_ProfileData) then
        print("|cffffd700MSUF:|r Profiler is |cffff0000OFF|r or has no data. Use |cffffff00/msufprofile on|r and fight first.")
        return
    end

    print("|cffffd700MSUF profile results:|r")

    local tmp = {}
    for key, v in pairs(MSUF_ProfileData) do
        table.insert(tmp, { key = key, time = v.time or 0, calls = v.calls or 0 })
    end
    table.sort(tmp, function(a, b)
        return (a.time or 0) > (b.time or 0)
    end)

    for _, e in ipairs(tmp) do
        local avg = (e.calls > 0) and (e.time / e.calls) or 0
        print(string.format("  %s - calls: %d, total: %.2f ms, avg: %.4f ms", e.key, e.calls, e.time, avg))
    end
end




-- Internal MSUF edit mode flag (NOT Blizzard Edit Mode)
local MSUF_UnitEditModeActive = false
-- Tracks which unit/options tab is currently selected in the MSUF options
local MSUF_CurrentOptionsKey = nil
-- Welche Unit wird aktuell im MSUF Edit Mode bearbeitet? (player/target/...)
local MSUF_CurrentEditUnitKey = nil
-- Aktueller Edit-Mode: false = Position, true = Size
local MSUF_EditModeSizing = false

-- OPTIONAL: LibSharedMedia-3.0
------------------------------------------------------
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

------------------------------------------------------
-- INTERNAL FONT LIST (Fallback)
------------------------------------------------------
-- Wenn Fonts später registriert werden (z.B. durch andere Addons),
-- sofort Dropdown + Fonts neu anwenden.
if LSM and not MSUF_LSM_FontCallbackRegistered then
    MSUF_LSM_FontCallbackRegistered = true

    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediatype, key)
        if mediatype ~= "font" then return end

        -- Dropdown-Liste neu bauen
        if MSUF_RebuildFontChoices then
            MSUF_RebuildFontChoices()
        end

        -- Wenn der gerade gewählte Font jetzt verfügbar ist -> sofort anwenden
        if MSUF_DB and MSUF_DB.general and MSUF_DB.general.fontKey == key then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if UpdateAllFonts then
                        UpdateAllFonts()
                    end
                end)
            elseif UpdateAllFonts then
                UpdateAllFonts()
            end
        end
    end)
end
local FONT_LIST = {
-- Default in-game fonts only to avoid issues with missing addon fonts
    {
        key  = "FRIZQT",
        name = "Friz Quadrata (default)",
        path = "Fonts\\FRIZQT__.TTF",
    },  

{
        key  = "ARIALN",
        name = "Arial (default)",
        path = "Fonts\\ARIALN.TTF",
    },
    {
        key  = "MORPHEUS",
        name = "Morpheus (default)",
        path = "Fonts\\MORPHEUS.TTF",
    },
    {
        key  = "SKURRI",
        name = "Skurri (default)",
        path = "Fonts\\SKURRI.TTF",
    },
}
-- vordefinierte Font-Farben für das Dropdown
local MSUF_FONT_COLORS = {
    white     = {1.0, 1.0, 1.0},
    black     = {0.0, 0.0, 0.0},
    red       = {1.0, 0.0, 0.0},
    green     = {0.0, 1.0, 0.0},
    blue      = {0.0, 0.0, 1.0},
    yellow    = {1.0, 1.0, 0.0},
    cyan      = {0.0, 1.0, 1.0},
    magenta   = {1.0, 0.0, 1.0},
    orange    = {1.0, 0.5, 0.0},
    purple    = {0.6, 0.0, 0.8},
    pink      = {1.0, 0.6, 0.8},
    turquoise = {0.0, 0.9, 0.8},
    grey      = {0.5, 0.5, 0.5},
    brown     = {0.6, 0.3, 0.1},
    gold      = {1.0, 0.85, 0.1},
}
-- Kleine FontObjects für das Font-Dropdown, damit jeder Eintrag in seiner eigenen Schrift angezeigt wird
local MSUF_FontPreviewObjects = {}

local function MSUF_GetFontPreviewObject(key)
    if not key or key == "" then
        return GameFontHighlightSmall
    end

    -- einmal erstellen, dann wiederverwenden
    local obj = MSUF_FontPreviewObjects[key]
    if not obj then
        obj = CreateFont("MSUF_FontPreview_" .. tostring(key))
        MSUF_FontPreviewObjects[key] = obj
    end

    -- Pfad für diesen Key suchen (LSM → interne FONT_LIST → Fallback)
    local path
    if LSM then
        local p = LSM:Fetch("font", key, false)
        if p then
            path = p
        end
    end

    if not path then
        path = GetInternalFontPathByKey(key) or FONT_LIST[1].path
    end

    -- feste Vorschaugröße reicht, es geht nur um den Look
    obj:SetFont(path, 14, "")

    return obj
end
local function MSUF_GetColorFromKey(key, fallbackColor)
    if type(key) ~= "string" then
        if fallbackColor then
            return fallbackColor
        end
        return CreateColor(1, 1, 1, 1)
    end

    local normalized = string.lower(key)
    local rgb = MSUF_FONT_COLORS[normalized]
    if rgb then
        local r, g, b = rgb[1], rgb[2], rgb[3]
        return CreateColor(r or 1, g or 1, b or 1, 1)
    end

    if fallbackColor then
        return fallbackColor
    end

    return CreateColor(1, 1, 1, 1)
end


MSUF_DARK_TONES = {
    black    = {0.0, 0.0, 0.0},
    darkgray = {0.08, 0.08, 0.08},
    softgray = {0.16, 0.16, 0.16},
}

function GetInternalFontPathByKey(key)
    if not key then return nil end
    for _, info in ipairs(FONT_LIST) do
        if info.key == key or info.name == key then
            return info.path
        end
    end
    return nil
end

------------------------------------------------------
-- SAVEDVARIABLES
------------------------------------------------------

-- Runtime toggle: show boss test frames
MSUF_BossTestMode = MSUF_BossTestMode or false

-- Zentrales Warn-Overlay, falls der Cooldown-Manager fehlt
local MSUF_CooldownWarningFrame

function EnsureDB()
    if not MSUF_DB then
        MSUF_DB = {}
    end

    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    -- Default to FRIZQT; migrate old EXPRESSWAY setting to FRIZQT as well
    if g.fontKey == nil or g.fontKey == "EXPRESSWAY" then
        g.fontKey = "FRIZQT"
    end
-- Anchor: default to UIParent, not the cooldown frame.
if g.anchorName == nil then
    g.anchorName = "UIParent"
end

-- If this is an old profile that still has "EssentialCooldownViewer"
-- as anchor from older versions, you now need to explicitly enable
-- "Anchor to cooldown manager" in the options if you want that behavior.
if g.anchorToCooldown == nil then
    g.anchorToCooldown = false
end
    -- Snap-Option für den internen MSUF Edit Mode
    if g.editModeSnapToGrid == nil then
        g.editModeSnapToGrid = true -- Standard: Snap an (wie Blizzard)
    end
 if g.darkMode == nil then
        g.darkMode = true
    end
    if g.darkBarTone == nil then
        g.darkBarTone = "black"
    end
    -- NEU: Helligkeit des Dark-Mode-Hintergrunds (0.10–0.40)
    if g.darkBgBrightness == nil then
        g.darkBgBrightness = 0.25      -- 25% Grau als Standard
    end
    if g.enableGradient == nil then
        g.enableGradient = true
    end
    if g.gradientStrength == nil then
        g.gradientStrength = 0.45
    end
        -- Edit Mode Hintergrund-Alpha (0.10–0.80)
    if g.editModeBgAlpha == nil or type(g.editModeBgAlpha) ~= "number" then
        g.editModeBgAlpha = 0.5
    else
        if g.editModeBgAlpha < 0.1 then
            g.editModeBgAlpha = 0.1
        elseif g.editModeBgAlpha > 0.8 then
            g.editModeBgAlpha = 0.8
        end
    end
    if g.useClassColors == nil then
        g.useClassColors = false
    end
    -- barMode steuert, ob Dark Mode oder Class Color Mode aktiv ist
    if g.barMode == nil then
        if g.useClassColors then
            g.barMode = "class"
        elseif g.darkMode then
            g.barMode = "dark"
        else
            g.barMode = "dark"
            g.darkMode = true
            g.useClassColors = false
        end
    end
    -- Bar border defaults
    if g.useBarBorder == nil then
        g.useBarBorder = true
    end
    if g.barBorderStyle == nil then
        g.barBorderStyle = "THIN"
    end
    if g.boldText == nil then
        g.boldText = false
    end
    -- NEW: allow disabling any black outline around the text
    if g.noOutline == nil then
        g.noOutline = false
    end
    if g.nameClassColor == nil then
        g.nameClassColor = true
    end
    if g.npcNameRed == nil then
        g.npcNameRed = false
    end
    if g.fontColor == nil then
    g.fontColor = "white"
    end

        if g.textBackdrop == nil then
        g.textBackdrop = false
    end
    -- Mouseover-Highlight: ab jetzt nur noch Farb-Keys als String.
    -- Ältere SavedVariables können hier Tabellen oder unbekannte Werte haben.
    if g.highlightEnabled == nil then
        g.highlightEnabled = true
    end
    if type(g.highlightColor) ~= "string" then
        -- alte gespeicherte Werte (z.B. Tabellen) -> auf Standard zurücksetzen
        g.highlightColor = "white"
    else
        g.highlightColor = string.lower(g.highlightColor)
        -- falls ein unbekannter String drinsteht -> ebenfalls auf Standard setzen
        if not MSUF_FONT_COLORS[g.highlightColor] then
            g.highlightColor = "white"
        end
    end
    -- Global unit update interval (seconds) used for event throttling.
    if g.frameUpdateInterval == nil or type(g.frameUpdateInterval) ~= "number" then
        g.frameUpdateInterval = 0.05
    end
    -- keep global in sync so event handler can read without extra upvalues
    MSUF_FrameUpdateInterval = g.frameUpdateInterval

    -- Global castbar update interval (seconds) for castbar OnUpdate throttling
    if g.castbarUpdateInterval == nil or type(g.castbarUpdateInterval) ~= "number" then
        g.castbarUpdateInterval = 0.02
    end
    MSUF_CastbarUpdateInterval = g.castbarUpdateInterval

    -- Unit info tooltip panel toggle (player/target/focus/ToT/pet/boss)
    if g.disableUnitInfoTooltips == nil then
        g.disableUnitInfoTooltips = false
    end

    -- Tooltip style for the custom info panel: "classic" vs "modern"
    if g.unitInfoTooltipStyle == nil then
        g.unitInfoTooltipStyle = "classic"
    end


    
        -- Castbar colors (string keys mapped via MSUF_FONT_COLORS)
    if g.castbarInterruptibleColor == nil then
        g.castbarInterruptibleColor = "turquoise"
    end
    if g.castbarNonInterruptibleColor == nil then
        g.castbarNonInterruptibleColor = "red"
    end
    if g.castbarInterruptColor == nil then
        g.castbarInterruptColor = "red"
    end
    -- Castbar fill direction: "RTL" (default) or "LTR"
    if g.castbarFillDirection == nil then
        g.castbarFillDirection = "RTL"
    end

-- Castbar toggles
    if g.enableTargetCastbar == nil then
        g.enableTargetCastbar = true
    end
    if g.enableFocusCastbar == nil then
        g.enableFocusCastbar = true
    end
    if g.enablePlayerCastbar == nil then
        g.enablePlayerCastbar = true
    end

      -- Additional castbar visual settings
    if g.castbarShowIcon == nil then
        g.castbarShowIcon = true
    end
    if g.castbarShowSpellName == nil then
        g.castbarShowSpellName = true
    end

    -- Grace period for castbars in milliseconds (used by slider)
    if g.castbarGraceMs == nil then
        g.castbarGraceMs = 120   -- Standard: 120 ms
    end

    if g.castbarSpellNameFontSize == nil then
        -- 0 = use Blizzard default font size for spell name
        g.castbarSpellNameFontSize = 0
    end

    if g.castbarIconOffsetX == nil then
        g.castbarIconOffsetX = 0
    end
    if g.castbarIconOffsetY == nil then
        g.castbarIconOffsetY = 0
    end


    -- Castbar offsets (relative positioning)
    if g.castbarTargetOffsetX == nil then
        g.castbarTargetOffsetX = 65
    end
    if g.castbarTargetOffsetY == nil then
        g.castbarTargetOffsetY = -15
    end
    if g.castbarFocusOffsetX == nil then
        g.castbarFocusOffsetX = g.castbarTargetOffsetX or 65
    end
    if g.castbarFocusOffsetY == nil then
        g.castbarFocusOffsetY = g.castbarTargetOffsetY or -15
    end

    if g.castbarPlayerOffsetX == nil then
        g.castbarPlayerOffsetX = 0
    end
    if g.castbarPlayerOffsetY == nil then
        g.castbarPlayerOffsetY = 5
    end
        -- Player cast time text offsets (Timer rechts auf der Leiste)
    if g.castbarPlayerTimeOffsetX == nil then
        g.castbarPlayerTimeOffsetX = -2
    end
    if g.castbarPlayerTimeOffsetY == nil then
        g.castbarPlayerTimeOffsetY = 0
    end
    -- Global castbar size (applies to all MSUF castbars)
    if g.castbarGlobalWidth == nil then
        g.castbarGlobalWidth = 200   -- Standardbreite
    end
    if g.castbarGlobalHeight == nil then
        g.castbarGlobalHeight = 18   -- Standardhöhe
    end

    if g.castbarPlayerPreviewEnabled == nil then
        g.castbarPlayerPreviewEnabled = false
    end

if g.targetAuraFilter == nil then
        g.targetAuraFilter = "ALL"
    end

    -- Target aura bar positioning (buff/debuff row above target)
    if g.targetAuraWidth == nil then g.targetAuraWidth = 200 end
    if g.targetAuraHeight == nil then g.targetAuraHeight = 18 end
    if g.targetAuraScale == nil then g.targetAuraScale = 1 end
    if g.targetAuraAlpha == nil then g.targetAuraAlpha = 1 end
    if g.targetAuraOffsetX == nil then g.targetAuraOffsetX = 0 end
    if g.targetAuraOffsetY == nil then g.targetAuraOffsetY = 2 end

    if g.fontSize == nil then
        g.fontSize = 14
    end
    if g.barTexture == nil then
        g.barTexture = "Blizzard"
    end

    -- Target aura display mode (buffs/debuffs visibility on target frame)
    if g.targetAuraDisplay == nil then
        -- "BUFFS_AND_DEBUFFS" = Buffs + Debuffs an (Standard)
        -- "BUFFS_ONLY"        = nur Buffs
        -- "DEBUFFS_ONLY"      = nur Debuffs
        -- "NONE"              = alles aus
        g.targetAuraDisplay = "BUFFS_AND_DEBUFFS"
    end

    -- HP text mode: controls how HP numbers are shown on the bars
    if g.hpTextMode == nil then
        -- "FULL_PLUS_PERCENT" = "142k (64%)" (default)
        -- "FULL_ONLY"         = "142k"
        -- "PERCENT_ONLY"      = "64%"
        g.hpTextMode = "FULL_PLUS_PERCENT"
    end

    -- NEU: Gesamt-Absorb im HP-Text anzeigen (Standard = AUS)
    if g.showTotalAbsorbAmount == nil then
        g.showTotalAbsorbAmount = false
    end

    -- NEW: Global toggle for the absorb overlay (white bar)
    if g.enableAbsorbBar == nil then
        g.enableAbsorbBar = true
    end

    -- NEW: Global toggle for the leader/assist icon (player/target frames)
    if g.showLeaderIcon == nil then
        g.showLeaderIcon = true
    end

    if MSUF_DB.bars == nil then
        MSUF_DB.bars = {}
    end
    if MSUF_DB.bars.showTargetPowerBar == nil then
        MSUF_DB.bars.showTargetPowerBar = true
    end

        if MSUF_DB.bars.showBossPowerBar == nil then
        MSUF_DB.bars.showBossPowerBar = true
    end
    if MSUF_DB.bars.showFocusPowerBar == nil then
        MSUF_DB.bars.showFocusPowerBar = true
    end
    if MSUF_DB.bars.showPlayerPowerBar == nil then
        MSUF_DB.bars.showPlayerPowerBar = true
    end
    -- NEW: Bars toggle for "Show bar border"
    if MSUF_DB.bars.showBarBorder == nil then
        MSUF_DB.bars.showBarBorder = true
    end

local function fill(key, defaults)
        MSUF_DB[key] = MSUF_DB[key] or {}
        local t = MSUF_DB[key]
        for k, v in pairs(defaults) do
            if t[k] == nil then
                t[k] = v
            end
        end
    end

    local textDefaults = {
        nameOffsetX   = 4,
        nameOffsetY   = -4,
        hpOffsetX     = -4,
        hpOffsetY     = -4,
        powerOffsetX  = -4,
        powerOffsetY  = 4,
    }

    -- Player: links von der Mitte, unten
    fill("player", {
        width     = 275,
        height    = 40,
        offsetX   = -260,
        offsetY   = -180,
        showName  = true,
        showHP    = true,
        showPower = true,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.player[k] == nil then MSUF_DB.player[k] = v end
    end

    -- Target: rechts von der Mitte, unten
    fill("target", {
        width     = 275,
        height    = 40,
        offsetX   = 260,
        offsetY   = -180,
        showName  = true,
        showHP    = true,
        showPower = true,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.target[k] == nil then MSUF_DB.target[k] = v end
    end

    -- Focus: rechts von der Mitte, eine Reihe höher
    fill("focus", {
        width     = 220,
        height    = 30,
        offsetX   = 260,
        offsetY   = -135,
        showName  = true,
        showHP    = false,
        showPower = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.focus[k] == nil then MSUF_DB.focus[k] = v end
    end
    fill("targettarget", {
        width     = 220,
        height    = 30,
        offsetX   = 275,
        offsetY   = -250,
        showName  = true,
        showHP    = true,
        showPower = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.targettarget[k] == nil then MSUF_DB.targettarget[k] = v end
    end

    fill("pet", {
        width     = 220,
        height    = 30,
        offsetX   = -275,
        offsetY   = -250,
        showName  = true,
        showHP    = true,
        showPower = true,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.pet[k] == nil then MSUF_DB.pet[k] = v end
    end

    fill("boss", {
        width     = 220,
        height    = 30,
        offsetX   = 400,
        offsetY   = -100,
        spacing   = -36,
        showName  = true,
        showHP    = true,
        showPower = true,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.boss[k] == nil then MSUF_DB.boss[k] = v end
    end
    for _, unitKey in ipairs({"player", "target", "targettarget", "focus", "pet", "boss"}) do
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        if MSUF_DB[unitKey].enabled == nil then
            MSUF_DB[unitKey].enabled = true
        end
    end

end

local function MSUF_GetFontPath()
    EnsureDB()
    local key = MSUF_DB.general.fontKey

    -- LSM OHNE stilles Fallback holen
    if LSM and key and key ~= "" then
        local path = LSM:Fetch("font", key, false)  -- <<< false statt true
        if path then
            return path
        end
    end

    -- interner Fallback (FONT_LIST)
    internalPath = GetInternalFontPathByKey(key)
    if internalPath then
        return internalPath
    end

    -- finaler Default
    return FONT_LIST[1].path
end

local function MSUF_GetFontFlags()
    EnsureDB()
    local g = MSUF_DB.general

    -- Wenn Outline deaktiviert ist: gar keine Umriss-Flags setzen
    if g.noOutline then
        return ""              -- kein OUTLINE / THICKOUTLINE
    elseif g.boldText then
        return "THICKOUTLINE"  -- fetter schwarzer Rand
    else
        return "OUTLINE"       -- normaler dünner Rand
    end
end


-- Get texture for castbars (player/target/focus).
-- Uses SharedMedia if a castbarTexture is configured;
-- otherwise falls back to the normal barTexture or default UI castbar texture.
function MSUF_GetCastbarTexture()
    EnsureDB()
    local defaultTex = "Interface\\TARGETINGFRAME\\UI-StatusBar"

    if not MSUF_DB or not MSUF_DB.general then
        return defaultTex
    end

    local key = MSUF_DB.general.castbarTexture

    -- Same logic as MSUF_GetBarTexture(): LSM:Fetch(..., true) with safe fallback
    if LSM and key and key ~= "" then
        local tex = LSM:Fetch("statusbar", key, true)
        if tex then
            return tex
        end
    end

    -- fallback: use normal bar texture
    if MSUF_GetBarTexture then
        local tex = MSUF_GetBarTexture()
        if tex then
            return tex
        end
    end

    return defaultTex
end

-- Returns true if the MSUF castbar for a given unit should be active.
-- This respects the per-unit toggles in the options menu.
local function MSUF_IsCastbarEnabledForUnit(unit)
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}

    if unit == "player" then
        return g.enablePlayerCastbar ~= false
    elseif unit == "target" then
        return g.enableTargetCastbar ~= false
    elseif unit == "focus" then
        return g.enableFocusCastbar ~= false
    end

    -- Any other unit (pet, boss, etc.) – currently always enabled
    return true
end

-- Decide whether a castbar should use reverse fill based on DB setting and channeled state.
-- Returns true/false for StatusBar:SetReverseFill().
function MSUF_GetCastbarReverseFill(isChanneled)
    EnsureDB()
    local dir = (MSUF_DB and MSUF_DB.general and MSUF_DB.general.castbarFillDirection) or "RTL"

    -- "RTL" keeps the existing behaviour: normal casts fill right -> left, channels left -> right.
    -- "LTR" inverts it: normal casts fill left -> right, channels right -> left.
    if dir == "RTL" then
        return not isChanneled
    else
        return isChanneled and true or false
    end
end


-- Apply current castbar texture to ALL MSUF castbars (live + previews)
function MSUF_UpdateCastbarTextures()
    local tex = MSUF_GetCastbarTexture()
    if not tex then return end

    local function Apply(frame)
        if frame and frame.statusBar then
            frame.statusBar:SetStatusBarTexture(tex)
        end
        if frame and frame.backgroundBar then
            frame.backgroundBar:SetTexture(tex)
        end
    end

    -- live castbars
    Apply(MSUF_PlayerCastbar)
    Apply(MSUF_TargetCastbar)
    Apply(MSUF_FocusCastbar)

    -- previews
    Apply(MSUF_PlayerCastbarPreview)
    Apply(MSUF_TargetCastbarPreview)
    Apply(MSUF_FocusCastbarPreview)
end





function MSUF_GetBarTexture()
    EnsureDB()
    local defaultTex = "Interface\\Buttons\\WHITE8x8"

    -- falls DB oder general nicht existiert, verwende Fallback
    if not MSUF_DB or not MSUF_DB.general then
        return defaultTex
    end

    local key = MSUF_DB.general.barTexture

    -- Wenn kein LibSharedMedia, immer Fallback
    if not LSM then
        return defaultTex
    end

    -- Wenn ein Key gesetzt ist, versuche, ihn über LSM zu holen
    if key and key ~= "" then
        local tex = LSM:Fetch("statusbar", key, true) -- true = still fallback on failure
        if tex then
            return tex
        end
    end

    -- Fallback
    return defaultTex
end

------------------------------------------------------
-- PROFILE SERIALIZATION
------------------------------------------------------
local function MSUF_SerializeDB()
    EnsureDB()

    local function valToStr(v)
        local tv = type(v)
        if tv == "number" then
            return tostring(v)
        elseif tv == "boolean" then
            return v and "true" or "false"
        elseif tv == "string" then
            return string.format("%q", v)
        else
            return "nil"
        end
    end

    local function keyToStr(k)
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
            return k
        else
            return "[" .. string.format("%q", k) .. "]"
        end
    end

    local function serTable(t, indent)
        indent = indent or ""
        local indent2 = indent .. "  "
        local lines = {}
        table.insert(lines, "{\n")
        for k, v in pairs(t) do
            local kStr = keyToStr(k)
            if type(v) == "table" then
                table.insert(lines, indent2 .. kStr .. " = " .. serTable(v, indent2) .. ",\n")
            else
                table.insert(lines, indent2 .. kStr .. " = " .. valToStr(v) .. ",\n")
            end
        end
        table.insert(lines, indent .. "}")
        return table.concat(lines)
    end

    local body = serTable(MSUF_DB, "")
    return "return " .. body
end

local function MSUF_ImportFromString(str)
    if not str or not str:match("%S") then
        print("|cffff0000MSUF:|r Import failed (empty string).")
        return
    end

    local func, err = loadstring(str)
    if not func then
        func, err = loadstring("return " .. str)
    end
    if not func then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(err))
        return
    end

    local ok, tbl = pcall(func)
    if not ok then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(tbl))
        return
    end
    if type(tbl) ~= "table" then
        print("|cffff0000MSUF:|r Import failed: not a table.")
        return
    end

    MSUF_DB = tbl
    EnsureDB()
    print("|cff00ff00MSUF:|r Profile imported.")
end

------------------------------------------------------
-- UNIT → CONFIG KEY
------------------------------------------------------
local function GetConfigKeyForUnit(unit)
    if unit == "player"
        or unit == "target"
        or unit == "focus"
        or unit == "targettarget"
        or unit == "pet"
    then
        return unit
    elseif unit and unit:match("^boss%d+$") then
        return "boss"
    end
    return nil
end

------------------------------------------------------
-- ANCHOR SELECTION
------------------------------------------------------
local function MSUF_GetAnchorFrame()
    EnsureDB()
    local g = MSUF_DB.general or {}

    -- 1) Explizit an den Cooldown-Manager ankern
    if g.anchorToCooldown then
        local ecv = _G["EssentialCooldownViewer"]
        if ecv and ecv:IsShown() then
            return ecv
        end
        -- Solange der Cooldownmanager nicht sichtbar ist, einfach an den Bildschirm ankern
        return UIParent
    end

    -- 2) Benutzerdefinierter Anchor-Name (aber nicht mehr stillschweigend der Cooldown-Frame)
    local anchorName = g.anchorName
    if anchorName and anchorName ~= "" and anchorName ~= "EssentialCooldownViewer" then
        local f = _G[anchorName]
        if f and f:IsShown() then
            return f
        end
    end

    -- 3) Fallback: Bildschirm
    return UIParent
end
------------------------------------------------------
-- Funktion für den Edit-Mode (bugfix)
------------------------------------------------------
local function MSUF_IsInEditMode()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end
------------------------------------------------------
-- Make Blizzard Options / Settings movable
------------------------------------------------------
local function MSUF_MakeBlizzardOptionsMovable()
    -- Dragonflight Settings-Panel
    local frame = _G.SettingsPanel

    -- Fallback für ältere Clients
    if not frame then
        frame = _G.InterfaceOptionsFrame or _G.VideoOptionsFrame or _G.AudioOptionsFrame
    end

    if not frame or frame.MSUF_Movable then
        return
    end
    frame.MSUF_Movable = true

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")

    local oldDragStart = frame:GetScript("OnDragStart")
    local oldDragStop  = frame:GetScript("OnDragStop")

    frame:SetScript("OnDragStart", function(self, ...)
        if oldDragStart then
            oldDragStart(self, ...)
        end
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self, ...)
        self:StopMovingOrSizing()
        if oldDragStop then
            oldDragStop(self, ...)
        end
    end)
end

------------------------------------------------------

------------------------------------------------------
-- Castbar Edit Mode Button (nur für Castbars)
------------------------------------------------------
local function MSUF_InitPlayerCastbarPreviewToggle()
    if not MSUF_DB or not MSUF_DB.general then
        return
    end

    -- Ein beliebiges Element im Castbar-Tab holen
    local playerGroup = _G["MSUF_CastbarPlayerGroup"]
    if not playerGroup then
        return
    end

    local castbarGroup = playerGroup:GetParent() or playerGroup
    local anchorParent = castbarGroup  -- gesamte Castbar-Seite

    -- Alte Checkbox-Version, falls noch existiert, komplett verstecken
    local oldCB = _G["MSUF_CastbarPlayerPreviewCheck"]
    if oldCB then
        oldCB:Hide()
        oldCB:SetScript("OnClick", nil)
        oldCB:SetScript("OnShow", nil)
    end

    -- Neuen Button anlegen oder wiederverwenden
    local btn = _G["MSUF_CastbarEditModeButton"]
    if not btn then
        btn = CreateFrame("Button", "MSUF_CastbarEditModeButton", anchorParent, "UIPanelButtonTemplate")
        btn:SetSize(160, 21)
        -- Position: oben rechts im Castbar-Tab, ungefähr unter dem "Profiles" Tab
        btn:SetPoint("TOPRIGHT", anchorParent, "TOPRIGHT", -175, -152)

        local fs = btn:GetFontString()
        if fs then
            fs:SetFontObject("GameFontNormal")
        end
    end

    local function UpdateButtonLabel()
        EnsureDB()
        local g       = MSUF_DB.general or {}
        local active  = g.castbarPlayerPreviewEnabled and true or false

        if active then
            btn:SetText("Castbar Edit Mode: ON")
        else
            btn:SetText("Castbar Edit Mode: OFF")
        end
    end

    btn:SetScript("OnClick", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}

        -- Toggle nur für Castbar-Preview
        g.castbarPlayerPreviewEnabled = not (g.castbarPlayerPreviewEnabled and true or false)

        if g.castbarPlayerPreviewEnabled then
            print("|cffffd700MSUF:|r Castbar Edit Mode |cff00ff00ON|r – drag player/target/focus castbars with the mouse.")
        else
            print("|cffffd700MSUF:|r Castbar Edit Mode |cffff0000OFF|r.")
        end

        if MSUF_UpdatePlayerCastbarPreview then
            MSUF_UpdatePlayerCastbarPreview()
        end

        UpdateButtonLabel()
    end)

    btn:SetScript("OnShow", UpdateButtonLabel)

    -- Initialer Sync nach dem Laden
    UpdateButtonLabel()
    btn:Show()
end

------------------------------------------------------
-- HIDE BLIZZARD UNITFRAMES
------------------------------------------------------
local function KillFrame(frame, allowInEditMode)
    if not frame then return end

    -- Alle Events abmelden und Frame verstecken
    if frame.UnregisterAllEvents then
        frame:UnregisterAllEvents()
    end
    frame:Hide()

    -- Falls Blizzard (Edit Mode etc.) später versucht, das Frame wieder zu zeigen,
    -- sofort wieder verstecken – außer wir erlauben explizit Edit Mode.
    frame:SetScript("OnShow", function(f)
        if allowInEditMode and MSUF_IsInEditMode and MSUF_IsInEditMode() then
            return
        end
        f:Hide()
    end)

    -- Sicherheit: Klicks abschalten
    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
end

-- TargetFrame-Visuals und Auren weg, falls das Frame NICHT hart gekillt wird
local function MSUF_HideBlizzardTargetVisuals()
    if not TargetFrame then return end

    local function KillChildFrame(child)
        if not child then return end
        if child.UnregisterAllEvents then
            child:UnregisterAllEvents()
        end
        child:Hide()
        child:SetScript("OnShow", function(f) f:Hide() end)
    end

    -- Hauptgrafik + Bars
    KillChildFrame(TargetFrame.TargetFrameContainer)
    KillChildFrame(TargetFrame.TargetFrameContent)
    KillChildFrame(TargetFrame.healthbar)
    KillChildFrame(TargetFrame.manabar)
    KillChildFrame(TargetFrame.powerBarAlt)
    KillChildFrame(TargetFrame.overAbsorbGlow)
    KillChildFrame(TargetFrame.overHealAbsorbGlow)
    KillChildFrame(TargetFrame.totalAbsorbBar)
    KillChildFrame(TargetFrame.tempMaxHealthLossBar)
    KillChildFrame(TargetFrame.myHealPredictionBar)
    KillChildFrame(TargetFrame.otherHealPredictionBar)
    KillChildFrame(TargetFrame.name)
    KillChildFrame(TargetFrame.portrait)
    KillChildFrame(TargetFrame.threatIndicator)
    KillChildFrame(TargetFrame.threatNumericIndicator)

    -- Do NOT hide:
    --   TargetFrame.spellbar / TargetFrameSpellBar  (castbar, falls jemand Blizzard nutzt)
    --   TargetFrame.Selection                       (Blizzard Edit Mode Highlight)

    -- Klassische Buff/Debuff Buttons
    for i = 1, 40 do
        KillChildFrame(_G["TargetFrameBuff"..i])
        KillChildFrame(_G["TargetFrameDebuff"..i])
    end

    -- Dragonflight/Midnight AuraPools entleeren
    if TargetFrame.auraPools and TargetFrame.auraPools.ReleaseAll then
        TargetFrame.auraPools:ReleaseAll()
    end

    if not TargetFrame.MSUF_AurasHooked and TargetFrame.UpdateAuras then
        TargetFrame.MSUF_AurasHooked = true
        hooksecurefunc(TargetFrame, "UpdateAuras", function(frame)
            if frame ~= TargetFrame then return end
            if frame.auraPools and frame.auraPools.ReleaseAll then
                frame.auraPools:ReleaseAll()
            end
        end)
    end

    -- Und sicherheitshalber auch die Klickfläche aus:
    if TargetFrame.EnableMouse then
        TargetFrame:EnableMouse(false)
    end
end

-- FocusFrame-Visuals/Auren weg
local function MSUF_HideBlizzardFocusVisuals()
    if not FocusFrame then return end

    local function KillChildFrame(child)
        if not child then return end
        if child.UnregisterAllEvents then
            child:UnregisterAllEvents()
        end
        child:Hide()
        if child.EnableMouse then
            child:EnableMouse(false)
        end
        child:SetScript("OnShow", function(f) f:Hide() end)
        if child.SetScript then
            child:SetScript("OnEnter", nil)
            child:SetScript("OnLeave", nil)
        end
    end

    -- Hauptgrafik + Bars
    KillChildFrame(FocusFrame.TargetFrameContainer)
    KillChildFrame(FocusFrame.TargetFrameContent)
    KillChildFrame(FocusFrame.healthbar)
    KillChildFrame(FocusFrame.manabar)
    KillChildFrame(FocusFrame.powerBarAlt)
    KillChildFrame(FocusFrame.overAbsorbGlow)
    KillChildFrame(FocusFrame.overHealAbsorbGlow)
    KillChildFrame(FocusFrame.totalAbsorbBar)
    KillChildFrame(FocusFrame.tempMaxHealthLossBar)
    KillChildFrame(FocusFrame.myHealPredictionBar)
    KillChildFrame(FocusFrame.otherHealPredictionBar)
    KillChildFrame(FocusFrame.name)
    KillChildFrame(FocusFrame.portrait)
    KillChildFrame(FocusFrame.threatIndicator)
    KillChildFrame(FocusFrame.threatNumericIndicator)

    -- FocusFrameSpellBar & FocusFrame.Selection lassen wir für Fallback / Edit Mode

    for i = 1, 40 do
        KillChildFrame(_G["FocusFrameBuff"..i])
        KillChildFrame(_G["FocusFrameDebuff"..i])
    end

    if FocusFrame.auraPools and FocusFrame.auraPools.ReleaseAll then
        FocusFrame.auraPools:ReleaseAll()
    end

    if not FocusFrame.MSUF_AurasHooked and FocusFrame.UpdateAuras then
        FocusFrame.MSUF_AurasHooked = true
        hooksecurefunc(FocusFrame, "UpdateAuras", function(frame)
            if frame ~= FocusFrame then return end
            if frame.auraPools and frame.auraPools.ReleaseAll then
                frame.auraPools:ReleaseAll()
            end
        end)
    end

    if FocusFrame.EnableMouse then
        FocusFrame:EnableMouse(false)
    end
end
-- Zentraler Schalter: alle Blizzard-Unitframes ausschalten
local function HideDefaultFrames()
    EnsureDB()
    local g = MSUF_DB.general or {}

    -- Wenn der User das explizit AUS hat, nichts anfassen
    if g.disableBlizzardUnitFrames == false then
        return
    end

    --------------------------------------------------
    -- Player / ToT / Pet komplett killen
    --------------------------------------------------
    KillFrame(PlayerFrame)
    KillFrame(TargetFrameToT)
    KillFrame(PetFrame)

    --------------------------------------------------
    -- Target + Focus hart killen (gegen Phantom-Klickbereiche)
    --------------------------------------------------
    KillFrame(TargetFrame)
    KillFrame(FocusFrame)

    --------------------------------------------------
    -- Boss-Frames + Boss-Container komplett killen
    --------------------------------------------------
    for i = 1, MSUF_MAX_BOSS_FRAMES do
        local bossFrame = _G["Boss"..i.."TargetFrame"]
        KillFrame(bossFrame) -- kein allowInEditMode: immer tot, auch im Blizzard Edit Mode
    end

    -- Der Container, der im Edit Mode als gelbes "Boss Frames" Overlay auftaucht
    if BossTargetFrameContainer then
        KillFrame(BossTargetFrameContainer)

        -- Und das Edit-Mode-Selection-Overlay darauf ebenfalls ausschalten
        if BossTargetFrameContainer.Selection then
            local sel = BossTargetFrameContainer.Selection
            if sel.UnregisterAllEvents then
                sel:UnregisterAllEvents()
            end
            if sel.EnableMouse then
                sel:EnableMouse(false)
            end
            sel:Hide()
            if sel.SetScript then
                sel:SetScript("OnShow", function(f) f:Hide() end)
                sel:SetScript("OnEnter", nil)
                sel:SetScript("OnLeave", nil)
            end
        end
    end

    --------------------------------------------------
    -- Zur Sicherheit trotzdem noch die Visual-Strips laufen lassen
    -- (falls Blizzard intern ChildFrames nachlädt)
    --------------------------------------------------
    MSUF_HideBlizzardTargetVisuals()
    MSUF_HideBlizzardFocusVisuals()
end

------------------------------------------------------
-- GLOBAL UNITFRAMES TABLE
------------------------------------------------------
local UnitFrames = {}
local MSUF_GridFrame
------------------------------------------------------
-- Helper: Aktuellen Grid-Step aus Slider/DB holen
------------------------------------------------------
local function MSUF_GetCurrentGridStep()
    local MIN, MAX = 8, 64
    local step

    -- 1. Prio: Live-Wert aus dem Slider
    local slider = _G["MSUF_EditModeGridSlider"]
    if slider and slider.GetValue then
        step = slider:GetValue()
    elseif MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.editModeGridStep) == "number" then
        -- 2. fallback: gespeicherter Wert aus DB
        step = MSUF_DB.general.editModeGridStep
    else
        -- 3. fallback: Default
        step = 20
    end

    step = tonumber(step) or 20
    if step < MIN then step = MIN end
    if step > MAX then step = MAX end

    return step

end
------------------------------------------------------
-- Reset: aktuelles Edit-Frame auf Default-DB-Werte
-- (wir setzen nur width/height/offsetX/offsetY auf nil
--  und lassen EnsureDB() die Defaults neu füllen)
------------------------------------------------------
local function MSUF_ResetCurrentEditUnit()
    -- Nichts zu resetten, wenn kein Frame aktiv ist
    if not MSUF_CurrentEditUnitKey then
        return
    end

    if not EnsureDB or not MSUF_DB then
        return
    end

    -- DB sicherstellen
    EnsureDB()

    local key  = MSUF_CurrentEditUnitKey
    local conf = MSUF_DB[key]
    if not conf then
        return
    end

    -- Nur Size + Position zurücksetzen – Rest bleibt unberührt
    conf.width   = nil
    conf.height  = nil
    conf.offsetX = nil
    conf.offsetY = nil

    -- Defaults für diesen Key wiederherstellen
    EnsureDB()

    -- Einstellungen für genau dieses Key neu anwenden
    if ApplySettingsForKey then
        ApplySettingsForKey(key)
    elseif ApplyAllSettings then
        ApplyAllSettings()
    end

    -- Edit-Mode-Info aktualisieren, falls vorhanden
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end
end

local function MSUF_CreateGridFrame()
    if MSUF_GridFrame then
        return
    end

    -- DB sicherstellen
    if EnsureDB then
        EnsureDB()
    end

    local parent = UIParent
    local f = CreateFrame("Frame", "MSUF_EditGrid", parent)
    f:SetAllPoints(parent)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(1)
    -- Info-Text oben: welche Unit + Koordinaten
    local infoText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOP", UIParent, "TOP", 0, -40)
    infoText:SetJustifyH("CENTER")
    infoText:SetText("")
    f.infoText = infoText

    -- gespeicherte Alpha lesen
    local alpha = 0.5
    if MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.editModeBgAlpha) == "number" then
        alpha = MSUF_DB.general.editModeBgAlpha
    end

    -- gespeicherten Grid-Step lesen
    local step = 20
    if MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.editModeGridStep) == "number" then
        step = MSUF_DB.general.editModeGridStep
    end

    -- Dunkler Hintergrund
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, alpha)
    f.bg = bg

    -- Child-Frame nur für Grid-Linien
    local grid = CreateFrame("Frame", nil, f)
    grid:SetAllPoints()
    f.grid = grid
    --------------------------------------------------
    -- Mittelkreuz (Screen-Center)
    --------------------------------------------------
    -- Vertikale Linie (Mitte)
    local centerVert = f:CreateTexture(nil, "ARTWORK")
    centerVert:SetColorTexture(1, 1, 0, 0.6)  -- gelblich, gut sichtbar
    centerVert:SetPoint("TOP", f, "TOP", 0, 0)
    centerVert:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    centerVert:SetWidth(2)
    f.centerVertical = centerVert

    -- Horizontale Linie (Mitte)
    local centerHoriz = f:CreateTexture(nil, "ARTWORK")
    centerHoriz:SetColorTexture(1, 1, 0, 0.6)
    centerHoriz:SetPoint("LEFT", f, "LEFT", 0, 0)
    centerHoriz:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    centerHoriz:SetHeight(2)
    f.centerHorizontal = centerHoriz

    -- Grid zeichnen / neu zeichnen
    local function RebuildGrid(newStep)
        local s = math.floor(newStep or step or 20)
        if s < 8 then s = 8 end
        if s > 64 then s = 64 end

        step = s
        if MSUF_DB and MSUF_DB.general then
            MSUF_DB.general.editModeGridStep = s
        end

        local w = parent:GetWidth() or 0
        local h = parent:GetHeight() or 0

        f.gridLines = f.gridLines or {}
        local lines = f.gridLines

        -- erst mal alle verstecken
        for i = 1, #lines do
            lines[i]:Hide()
        end

        local idx = 1

        -- Vertikale Linien
        for x = 0, w, s do
            local tex = lines[idx]
            if not tex then
                tex = grid:CreateTexture(nil, "BACKGROUND")
                lines[idx] = tex
            end
            tex:ClearAllPoints()
            tex:SetColorTexture(1, 1, 1, 0.25)
            tex:SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0)
            tex:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", x, 0)
            tex:SetWidth(1)
            tex:Show()
            idx = idx + 1
        end

        -- Horizontale Linien
        for y = 0, h, s do
            local tex = lines[idx]
            if not tex then
                tex = grid:CreateTexture(nil, "BACKGROUND")
                lines[idx] = tex
            end
            tex:ClearAllPoints()
            tex:SetColorTexture(1, 1, 1, 0.25)
            tex:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
            tex:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 0, -y)
            tex:SetHeight(1)
            tex:Show()
            idx = idx + 1
        end

        -- übrige Texturen verstecken
        for i = idx, #lines do
            lines[i]:Hide()
        end
    end

    -- einmal initial zeichnen
    RebuildGrid(step)

    -- 🔹 Slider 1: Hintergrund-Alpha
    local alphaSlider = CreateFrame("Slider", "MSUF_EditModeAlphaSlider", f, "OptionsSliderTemplate")
    alphaSlider:SetOrientation("HORIZONTAL")
    alphaSlider:SetSize(200, 16)
    alphaSlider:SetPoint("TOP", UIParent, "TOP", 0, -80)
    alphaSlider:SetMinMaxValues(0.1, 0.8)
    alphaSlider:SetValueStep(0.05)
    alphaSlider:SetObeyStepOnDrag(true)
    alphaSlider:SetValue(alpha)

    local aName = alphaSlider:GetName()
    _G[aName .. "Low"]:SetText("10%")
    _G[aName .. "High"]:SetText("80%")
    _G[aName .. "Text"]:SetText("Edit Mode Background")

    alphaSlider:SetScript("OnValueChanged", function(self, value)
        if value < 0.1 then
            value = 0.1
        elseif value > 0.8 then
            value = 0.8
        end

        if MSUF_DB and MSUF_DB.general then
            MSUF_DB.general.editModeBgAlpha = value
        end
        if f.bg then
            f.bg:SetColorTexture(0, 0, 0, value)
        end
    end)

    f.alphaSlider = alphaSlider

    -- 🔹 Slider 2: Grid-Abstand
    local gridSlider = CreateFrame("Slider", "MSUF_EditModeGridSlider", f, "OptionsSliderTemplate")
    gridSlider:SetOrientation("HORIZONTAL")
    gridSlider:SetSize(200, 16)
    gridSlider:SetPoint("TOP", UIParent, "TOP", 0, -110) -- etwas unter dem Alpha-Slider
    gridSlider:SetMinMaxValues(8, 64)
    gridSlider:SetValueStep(2)
    gridSlider:SetObeyStepOnDrag(true)
    gridSlider:SetValue(step)

    local gName = gridSlider:GetName()
    _G[gName .. "Low"]:SetText("8")
    _G[gName .. "High"]:SetText("64")
    _G[gName .. "Text"]:SetText("Grid Size (px)")

    gridSlider:SetScript("OnValueChanged", function(self, value)
        RebuildGrid(value)
    end)

     f.gridSlider = gridSlider

    --------------------------------------------------
    -- Snap-to-grid Toggle-Button im Overlay
    --------------------------------------------------
    local snapBtn = CreateFrame("Button", "MSUF_EditModeSnapOverlay", f, "UIPanelButtonTemplate")
    snapBtn:SetSize(110, 22)
    snapBtn:SetPoint("TOP", gridSlider, "BOTTOM", 0, -8)

    -- kleine Helper-Funktion für Optik & Text
    local function UpdateSnapButtonVisual()
        EnsureDB()
        local g = MSUF_DB.general or {}
        local enabled = g.editModeSnapToGrid ~= false

        if enabled then
            snapBtn:SetText("Snap: ON")
            if snapBtn:GetFontString() then
                snapBtn:GetFontString():SetTextColor(1, 0.82, 0) -- gelblich
            end
        else
            snapBtn:SetText("Snap: OFF")
            if snapBtn:GetFontString() then
                snapBtn:GetFontString():SetTextColor(0.8, 0.8, 0.8) -- grau
            end
        end
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    if MSUF_DB.general.editModeSnapToGrid == nil then
        -- Standard: Snap an
        MSUF_DB.general.editModeSnapToGrid = true
    end

    snapBtn:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.editModeSnapToGrid = not MSUF_DB.general.editModeSnapToGrid
        UpdateSnapButtonVisual()
    end)
    --------------------------------------------------
    -- Mode-Toggle: Position vs Size
    --------------------------------------------------
      --------------------------------------------------
    -- Mode-Toggle: Position vs Size (RIESIG)
    --------------------------------------------------
    local modeBtn = CreateFrame("Button", "MSUF_EditModeModeButton", f, "UIPanelButtonTemplate")
    -- schön breit & hoch
    modeBtn:SetSize(260, 36)
    modeBtn:SetPoint("TOP", snapBtn, "BOTTOM", 0, -12)

    -- große Schrift
    local modeFS = modeBtn:GetFontString()
    if modeFS then
        local font, _, flags = modeFS:GetFont()
        modeFS:SetFont(font, 16, flags or "")
    end

    local function UpdateModeButtonVisual()
        if MSUF_EditModeSizing then
            modeBtn:SetText("MODE: SIZE")
        else
            modeBtn:SetText("MODE: POSITION")
        end
    end

    modeBtn:SetScript("OnClick", function(self)
        MSUF_EditModeSizing = not MSUF_EditModeSizing
        UpdateModeButtonVisual()
        if MSUF_UpdateEditModeInfo then
            MSUF_UpdateEditModeInfo()
        end
    end)

    UpdateModeButtonVisual()

    --------------------------------------------------
    -- Anchor to cooldown manager (shortcut in Edit Mode)
    --------------------------------------------------
    local anchorCheck = CreateFrame("CheckButton", "MSUF_EditModeAnchorToCooldownCheck", f, "UICheckButtonTemplate")
    anchorCheck:SetPoint("TOP", modeBtn, "BOTTOM", 0, -8)

    local anchorLabel = anchorCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    anchorLabel:SetPoint("LEFT", anchorCheck, "RIGHT", 4, 0)
    anchorLabel:SetText("Anchor to cooldown manager")
    anchorCheck.text = anchorLabel

    EnsureDB()
    anchorCheck:SetChecked(MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorToCooldown)

    anchorCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local enabled = self:GetChecked() and true or false
        MSUF_DB.general.anchorToCooldown = enabled
        -- Also drive the Blizzard CVar so the default cooldown UI is actually enabled/disabled
        MSUF_SetCooldownViewerEnabled(enabled)
        ApplyAllSettings()

        if enabled then
            -- Try to load + show the external cooldown manager so the anchor makes sense
            local addonName = "EssentialCooldownViewer"

            if LoadAddOn and not IsAddOnLoaded(addonName) then
                local ok, result = pcall(LoadAddOn, addonName)
                if not ok then
                    print("|cffffd700MSUF:|r Could not load cooldown manager addon '" .. addonName .. "'.")
                end
            end

            local ecv = _G["EssentialCooldownViewer"]
            if ecv and ecv.Show then
                ecv:Show()
            else
                print("|cffffd700MSUF:|r Cooldown manager anchor enabled, but 'EssentialCooldownViewer' was not found. Falling back to screen anchor.")
            end
        end
    end)

    --------------------------------------------------
    -- Custom anchor (frame name via /fstack)
    --------------------------------------------------
    local anchorNameLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    anchorNameLabel:SetPoint("TOP", anchorCheck, "BOTTOM", 0, -6)
    anchorNameLabel:SetText("Custom anchor frame name (/fstack)")

    local anchorNameInput = CreateFrame("EditBox", "MSUF_EditModeAnchorNameInput", f, "InputBoxTemplate")
    anchorNameInput:SetSize(220, 20)
    anchorNameInput:SetPoint("TOP", anchorNameLabel, "BOTTOM", 0, -4)
    anchorNameInput:SetAutoFocus(false)
    anchorNameInput:SetMaxLetters(64)

    EnsureDB()
    local initialAnchorName = MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorName or ""
    if initialAnchorName == nil then
        initialAnchorName = ""
    end
    anchorNameInput:SetText(initialAnchorName)

    local function MSUF_ApplyCustomAnchorNameFromEditBox()
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local txt = anchorNameInput:GetText() or ""
        txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
        if txt == "" then
            MSUF_DB.general.anchorName = nil
        else
            MSUF_DB.general.anchorName = txt
            -- When using a manual anchor, turn off the cooldown-manager anchor checkbox
            MSUF_DB.general.anchorToCooldown = false
            if anchorCheck and anchorCheck.SetChecked then
                anchorCheck:SetChecked(false)
            end
        end
        ApplyAllSettings()
    end

    anchorNameInput:SetScript("OnEnterPressed", function(self)
        MSUF_ApplyCustomAnchorNameFromEditBox()
        self:ClearFocus()
    end)

    anchorNameInput:SetScript("OnEditFocusLost", function(self)
        MSUF_ApplyCustomAnchorNameFromEditBox()
    end)

    anchorNameInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        EnsureDB()
        local current = MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorName or ""
        if current == nil then
            current = ""
        end
        anchorNameInput:SetText(current)
    end)

    --------------------------------------------------
    -- Boss preview toggle (Edit Mode only)
    --------------------------------------------------
    local bossPreviewCheck = CreateFrame("CheckButton", "MSUF_EditModeBossPreviewCheck", f, "UICheckButtonTemplate")
    bossPreviewCheck:SetPoint("TOP", anchorNameInput, "BOTTOM", 0, -8)

    local bossLabel = bossPreviewCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    bossLabel:SetPoint("LEFT", bossPreviewCheck, "RIGHT", 4, 0)
    bossLabel:SetText("Preview boss frames")
    bossPreviewCheck.text = bossLabel

    bossPreviewCheck:SetChecked(MSUF_BossTestMode and true or false)

    bossPreviewCheck:SetScript("OnClick", function(self)
        MSUF_BossTestMode = self:GetChecked() and true or false

        -- Direkt alle Bossframes aktualisieren
        for i = 1, MSUF_MAX_BOSS_FRAMES do
            local f = _G["MSUF_boss" .. i]
            if f then
                if MSUF_BossTestMode and not InCombatLockdown() then
                    -- Für Preview sicher anzeigen
                    f:Show()
                    f:SetAlpha(1)
                end
                UpdateSimpleUnitFrame(f)
            end
        end
    end)
    --------------------------------------------------
    -- Exit-Button im Edit-Mode-Overlay
    --------------------------------------------------
    local exitBtn = CreateFrame("Button", "MSUF_EditModeExitButton", f, "UIPanelButtonTemplate")
    exitBtn:SetSize(130, 22)
    exitBtn:SetPoint("TOP", bossPreviewCheck, "BOTTOM", 0, -10)
    exitBtn:SetText("Exit Edit Mode")

    exitBtn:SetScript("OnClick", function()
        if not MSUF_UnitEditModeActive then
            return
        end

        -- Edit Mode aus
         MSUF_UnitEditModeActive = false
        MSUF_CurrentEditUnitKey = nil
   -- NEU: Castbar-Preview mit globalem Edit Mode synchronisieren
    MSUF_SyncCastbarEditModeWithUnitEdit()
        -- Grid sofort ausblenden
        if MSUF_GridFrame then
            MSUF_GridFrame:Hide()
        end

        -- Pfeile für alle Frames aktualisieren (wie in MSUF_UpdateEditModeVisuals)
        if UnitFrames then
            local pf = UnitFrames["player"]
            if pf and pf.UpdateEditArrows then pf:UpdateEditArrows() end

            local tf = UnitFrames["target"]
            if tf and tf.UpdateEditArrows then tf:UpdateEditArrows() end

            local ff = UnitFrames["focus"]
            if ff and ff.UpdateEditArrows then ff:UpdateEditArrows() end

            local pet = UnitFrames["pet"]
            if pet and pet.UpdateEditArrows then pet:UpdateEditArrows() end

            local tot = UnitFrames["targettarget"]
            if tot and tot.UpdateEditArrows then tot:UpdateEditArrows() end

            for i = 1, MSUF_MAX_BOSS_FRAMES do
                local bf = UnitFrames["boss" .. i]
                if bf and bf.UpdateEditArrows then
                    bf:UpdateEditArrows()
                end
            end
        end

        print("|cffffd700MSUF:|r Edit Mode |cffff0000OFF|r.")
    end)
    --------------------------------------------------
    -- Reset-Button: aktuelles Frame auf Defaults
    --------------------------------------------------
    local resetBtn = CreateFrame("Button", "MSUF_EditModeResetButton", f, "UIPanelButtonTemplate")
    resetBtn:SetSize(130, 22)
    resetBtn:SetPoint("TOP", exitBtn, "BOTTOM", 0, -6)
    resetBtn:SetText("Reset Frame")

    resetBtn:SetScript("OnClick", function()
        -- Nur im aktiven Edit Mode
        if not MSUF_UnitEditModeActive then
            return
        end

        -- Kein Frame ausgewählt -> kurze Info
        if not MSUF_CurrentEditUnitKey then
            if MSUF_GridFrame and MSUF_GridFrame.infoText then
                MSUF_GridFrame.infoText:SetText("Reset: Kein Frame ausgewählt – klicke zuerst ein Frame.")
            end
            return
        end

        if MSUF_ResetCurrentEditUnit then
            MSUF_ResetCurrentEditUnit()
        end
    end)

    f.resetButton = resetBtn

    -- Initialer Visual-State für Snap-Button
    UpdateSnapButtonVisual()

    f.snapButton = snapBtn
    f.exitButton = exitBtn

    f:Hide()
    MSUF_GridFrame = f
end
------------------------------------------------------
-- Edit Mode: Info-Text (Unit + X/Y Offsets)
------------------------------------------------------
local function MSUF_GetUnitLabelForKey(key)
    if key == "player" then
        return "Player"
    elseif key == "target" then
        return "Target"
    elseif key == "targettarget" then
        return "Target of Target"
    elseif key == "focus" then
        return "Focus"
    elseif key == "pet" then
        return "Pet"
    elseif key == "boss" then
        return "Boss"
    else
        return key or "Unknown"
    end
end

local function MSUF_UpdateEditModeInfo()
    if not MSUF_GridFrame or not MSUF_GridFrame.infoText then
        return
    end

    local textWidget = MSUF_GridFrame.infoText

    -- Wenn Edit Mode aus ist: Text + Hint leeren
    if not MSUF_UnitEditModeActive then
        textWidget:SetText("")
        if MSUF_GridFrame.modeHint then
            MSUF_GridFrame.modeHint:Hide()
        end
        return
    end

    EnsureDB()

    local key = MSUF_CurrentEditUnitKey
    if not key or not MSUF_DB[key] then
        -- Kein spezielles Frame aktiv: Mini-Info
        if MSUF_EditModeSizing then
            textWidget:SetText("MSUF Edit Mode – MODE: SIZE")
        else
            textWidget:SetText("MSUF Edit Mode – MODE: POSITION")
        end

        -- Hint-Text je nach Mode
        if MSUF_GridFrame.modeHint then
            if MSUF_EditModeSizing then
                MSUF_GridFrame.modeHint:SetText("|cff00ff00MODE: SIZE – drag & arrows change frame SIZE.|r")
            else
                MSUF_GridFrame.modeHint:SetText("|cffffff00MODE: POSITION – drag & arrows move frames. Click MODE for SIZE.|r")
            end
            MSUF_GridFrame.modeHint:Show()
        end
        return
    end

    local conf  = MSUF_DB[key]
    local label = MSUF_GetUnitLabelForKey(key)

    if MSUF_EditModeSizing then
        local w = conf.width or 0
        local h = conf.height or 0
        textWidget:SetText(string.format("Sizing: %s (W: %d, H: %d)", label, w, h))
    else
        local x = conf.offsetX or 0
        local y = conf.offsetY or 0
        textWidget:SetText(string.format("Editing: %s (X: %d, Y: %d)", label, x, y))
    end

    -- 🔽 HIER ist das, was ich in 3b meinte: Hint-Text am Ende anpassen
    if MSUF_GridFrame.modeHint then
        if MSUF_EditModeSizing then
            MSUF_GridFrame.modeHint:SetText("|cff00ff00MODE: SIZE – drag & arrows change frame SIZE.|r")
        else
            MSUF_GridFrame.modeHint:SetText("|cffffff00MODE: POSITION – drag & arrows move frames. Click MODE for SIZE.|r")
        end
        MSUF_GridFrame.modeHint:Show()
    end
end
-- Kleine +/- Buttons neben einem EditBox-Feld
-- onStep = Funktion, die nach jedem Klick ausgeführt wird (für "live apply")
local function MSUF_AttachStepperButtons(parent, editBox, onStep)
    if not parent or not editBox then return end

    local function Step(delta)
        local txt = editBox:GetText() or ""
        local val = tonumber(txt) or 0
        val = val + delta
        editBox:SetText(tostring(val))
        -- Cursor ans Ende setzen (sieht sauberer aus)
        editBox:SetCursorPosition(editBox:GetNumLetters())

        if type(onStep) == "function" then
            onStep()
        end
    end

    -- Minus-Button
    local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    minus:SetSize(16, 16)
    minus:SetText("-")
    minus:SetPoint("LEFT", editBox, "RIGHT", 2, 0)
    minus:SetScript("OnClick", function() Step(-1) end)

    -- Plus-Button
    local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    plus:SetSize(16, 16)
    plus:SetText("+")
    plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    plus:SetScript("OnClick", function() Step(1) end)

    return minus, plus
end
------------------------------------------------------
-- Edit Mode: X/Y + Width/Height Popup für Unitframes
------------------------------------------------------
local MSUF_PositionPopup

local function MSUF_OpenPositionPopup(unit, parent)
    -- Nur wenn MSUF-Edit-Mode aktiv ist und nicht im Kampf
    if not MSUF_UnitEditModeActive then
        return
    end
        -- Helper: liest die Editbox-Werte aus und wendet sie sofort an
    local function ApplyUnitPopupValues()
        if InCombatLockdown and InCombatLockdown() then
            print("|cffffd700MSUF:|r Position/Größe kann im Kampf nicht geändert werden.")
            return
        end

        EnsureDB()
        local pf = MSUF_PositionPopup
        if not pf or not pf.unit or not pf.parent then
            return
        end

        local key = GetConfigKeyForUnit(pf.unit)
        local conf = key and MSUF_DB[key]
        if not conf then
            return
        end

        local currentW = conf.width  or (pf.parent:GetWidth()  or 250)
        local currentH = conf.height or (pf.parent:GetHeight() or 40)

        local xVal = tonumber(pf.xBox:GetText() or "") or conf.offsetX or 0
        local yVal = tonumber(pf.yBox:GetText() or "") or conf.offsetY or 0
        local wVal = tonumber(pf.wBox:GetText() or "") or currentW
        local hVal = tonumber(pf.hBox:GetText() or "") or currentH

        -- einfache Limits
        if wVal < 80  then wVal = 80  end
        if wVal > 600 then wVal = 600 end
        if hVal < 20  then hVal = 20  end
        if hVal > 600 then hVal = 600 end

        conf.offsetX = xVal
        conf.offsetY = yVal
        conf.width   = wVal
        conf.height  = hVal

        -- Frames neu aufbauen
        if ApplySettingsForKey then
            ApplySettingsForKey(key)
        elseif ApplyAllSettings then
            ApplyAllSettings()
        end

        -- Options-Slider syncen, falls der entsprechende Tab offen ist
        if MSUF_CurrentOptionsKey == key then
            local xSlider = _G["MSUF_OffsetXSlider"]
            local ySlider = _G["MSUF_OffsetYSlider"]
            local wSlider = _G["MSUF_WidthSlider"]
            local hSlider = _G["MSUF_HeightSlider"]

            if xSlider and xSlider.SetValue then xSlider:SetValue(conf.offsetX or 0) end
            if ySlider and ySlider.SetValue then ySlider:SetValue(conf.offsetY or 0) end
            if wSlider and wSlider.SetValue then wSlider:SetValue(conf.width   or wVal) end
            if hSlider and hSlider.SetValue then hSlider:SetValue(conf.height  or hVal) end
        end

        -- Text im Grid oben aktualisieren
        if MSUF_UpdateEditModeInfo then
            MSUF_UpdateEditModeInfo()
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        print("|cffffd700MSUF:|r Position/Größe kann im Kampf nicht geändert werden.")
        return
    end
    if not unit or not parent then
        return
    end

    EnsureDB()
    local key = GetConfigKeyForUnit(unit)
    if not key then
        return
    end

    local conf = MSUF_DB[key]
    if not conf then
        return
    end

    -- Dieses Frame im Edit-Overlay als aktiv markieren
    MSUF_CurrentEditUnitKey = key
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end

    -- Popup einmalig erstellen
    if not MSUF_PositionPopup then
        local pf = CreateFrame("Frame", "MSUF_EditPositionPopup", UIParent, "BackdropTemplate")
        MSUF_PositionPopup = pf

        pf:SetSize(260, 190)
        pf:SetFrameStrata("TOOLTIP")
        pf:SetFrameLevel(9999)
        pf:SetClampedToScreen(true)
        pf:SetMovable(true)
        pf:EnableMouse(true)
        pf:RegisterForDrag("LeftButton")
        pf:SetScript("OnDragStart", pf.StartMoving)
        pf:SetScript("OnDragStop", pf.StopMovingOrSizing)

        pf:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })

        -- Titel
        local title = pf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -10)
        title:SetText("MSUF Edit")
        pf.title = title

        -- Offset X
        local xLabel = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        xLabel:SetPoint("TOPLEFT", 15, -35)
        xLabel:SetText("Offset X:")
        pf.xLabel = xLabel

        local xBox = CreateFrame("EditBox", "$parentXBox", pf, "InputBoxTemplate")
        xBox:SetSize(80, 20)
        xBox:SetPoint("LEFT", xLabel, "RIGHT", 8, 0)
        xBox:SetAutoFocus(false)
        pf.xBox = xBox
        pf.xMinus, pf.xPlus = MSUF_AttachStepperButtons(pf, xBox, ApplyUnitPopupValues)

        -- Offset Y
        local yLabel = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        yLabel:SetPoint("TOPLEFT", xLabel, "BOTTOMLEFT", 0, -8)
        yLabel:SetText("Offset Y:")
        pf.yLabel = yLabel

        local yBox = CreateFrame("EditBox", "$parentYBox", pf, "InputBoxTemplate")
        yBox:SetSize(80, 20)
        yBox:SetPoint("LEFT", yLabel, "RIGHT", 8, 0)
        yBox:SetAutoFocus(false)
        pf.yBox = yBox
        pf.yMinus, pf.yPlus = MSUF_AttachStepperButtons(pf, yBox, ApplyUnitPopupValues)

        -- Width
        local wLabel = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        wLabel:SetPoint("TOPLEFT", yLabel, "BOTTOMLEFT", 0, -12)
        wLabel:SetText("Width:")
        pf.wLabel = wLabel

        local wBox = CreateFrame("EditBox", "$parentWBox", pf, "InputBoxTemplate")
        wBox:SetSize(80, 20)
        wBox:SetPoint("LEFT", wLabel, "RIGHT", 8, 0)
        wBox:SetAutoFocus(false)
        pf.wBox = wBox
        pf.wMinus, pf.wPlus = MSUF_AttachStepperButtons(pf, wBox, ApplyUnitPopupValues)

        -- Height
        local hLabel = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hLabel:SetPoint("TOPLEFT", wLabel, "BOTTOMLEFT", 0, -8)
        hLabel:SetText("Height:")
        pf.hLabel = hLabel

        local hBox = CreateFrame("EditBox", "$parentHBox", pf, "InputBoxTemplate")
        hBox:SetSize(80, 20)
        hBox:SetPoint("LEFT", hLabel, "RIGHT", 8, 0)
        hBox:SetAutoFocus(false)
        pf.hBox = hBox
        pf.hMinus, pf.hPlus = MSUF_AttachStepperButtons(pf, hBox, ApplyUnitPopupValues)

        pf.xMinus, pf.xPlus = MSUF_AttachStepperButtons(pf, xBox)
        pf.yMinus, pf.yPlus = MSUF_AttachStepperButtons(pf, yBox)
        pf.wMinus, pf.wPlus = MSUF_AttachStepperButtons(pf, wBox)
        pf.hMinus, pf.hPlus = MSUF_AttachStepperButtons(pf, hBox)



        -- OK & Cancel Buttons
        local okBtn = CreateFrame("Button", "$parentOK", pf, "UIPanelButtonTemplate")
        okBtn:SetSize(70, 22)
        okBtn:SetPoint("BOTTOMRIGHT", -10, 10)
        okBtn:SetText(OKAY)
        pf.okBtn = okBtn

        local cancelBtn = CreateFrame("Button", "$parentCancel", pf, "UIPanelButtonTemplate")
        cancelBtn:SetSize(70, 22)
        cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -6, 0)
        cancelBtn:SetText(CANCEL)
        pf.cancelBtn = cancelBtn

        cancelBtn:SetScript("OnClick", function()
            MSUF_PositionPopup:Hide()
        end)

        -- OK-Button: Werte anwenden (für player/target/focus/ToT/pet/boss)
        okBtn:SetScript("OnClick", function()
            ApplyUnitPopupValues()
            MSUF_PositionPopup:Hide()
        end)
        -- Enter/Escape: Enter = OK, Escape = schließen
        local function OnEnterPressed(self)
            pf.okBtn:Click()
        end
        local function OnEscapePressed(self)
            MSUF_PositionPopup:Hide()
        end

        xBox:SetScript("OnEnterPressed", OnEnterPressed)
        yBox:SetScript("OnEnterPressed", OnEnterPressed)
        wBox:SetScript("OnEnterPressed", OnEnterPressed)
        hBox:SetScript("OnEnterPressed", OnEnterPressed)

        xBox:SetScript("OnEscapePressed", OnEscapePressed)
        yBox:SetScript("OnEscapePressed", OnEscapePressed)
        wBox:SetScript("OnEscapePressed", OnEscapePressed)
        hBox:SetScript("OnEscapePressed", OnEscapePressed)
    end

    -- Popup für die aktuelle Unit mit aktuellen Werten füllen
    local pf = MSUF_PositionPopup
    pf.unit   = unit
    pf.parent = parent

    local label = MSUF_GetUnitLabelForKey and MSUF_GetUnitLabelForKey(key) or unit
    pf.title:SetText(string.format("MSUF Edit – %s", label))

    local x = conf.offsetX or 0
    local y = conf.offsetY or 0
    local w = conf.width   or (parent and parent:GetWidth()  or 250)
    local h = conf.height  or (parent and parent:GetHeight() or 40)

    pf.xBox:SetText(tostring(x))
    pf.yBox:SetText(tostring(y))
    pf.wBox:SetText(tostring(math.floor(w + 0.5)))
    pf.hBox:SetText(tostring(math.floor(h + 0.5)))

    pf:ClearAllPoints()
    if parent and parent:GetCenter() then
        pf:SetPoint("CENTER", parent, "CENTER", 0, 0)
    else
        pf:SetPoint("CENTER")
    end

    pf:Show()
end

-- Spezieller Info-Text für Castbars im Edit Mode (X/Y oder W/H)
local function MSUF_UpdateCastbarEditInfo(unit)
    if not MSUF_GridFrame or not MSUF_GridFrame.infoText then
        return
    end
    if not MSUF_UnitEditModeActive then
        return
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local prefix
    local label
    if unit == "player" then
        prefix = "castbarPlayer"
        label  = "Player Castbar"
    elseif unit == "target" then
        prefix = "castbarTarget"
        label  = "Target Castbar"
    elseif unit == "focus" then
        prefix = "castbarFocus"
        label  = "Focus Castbar"
    else
        return
    end

    local textWidget = MSUF_GridFrame.infoText

    if MSUF_EditModeSizing then
        local w = g[prefix .. "BarWidth"]  or g.castbarGlobalWidth  or 0
        local h = g[prefix .. "BarHeight"] or g.castbarGlobalHeight or 0
        textWidget:SetText(string.format("Sizing: %s (W: %d, H: %d)", label, w, h))
    else
        local defaultX, defaultY
        if unit == "player" then
            defaultX, defaultY = 0, 5
        else
            defaultX, defaultY = 65, -15
        end

        local x = g[prefix .. "OffsetX"] or defaultX
        local y = g[prefix .. "OffsetY"] or defaultY
        textWidget:SetText(string.format("Editing: %s (X: %d, Y: %d)", label, x, y))
    end
end


local function MSUF_UpdateGridOverlay()
    -- Wenn Edit Mode aus ist: Grid aus
    if not MSUF_UnitEditModeActive then
        if MSUF_GridFrame then
            MSUF_GridFrame:Hide()
            if MSUF_GridFrame.modeHint then
                MSUF_GridFrame.modeHint:Hide()
            end
        end
        return
    end

    -- Im Kampf: Edit Mode + Grid deaktivieren
    if InCombatLockdown and InCombatLockdown() then
        if MSUF_GridFrame then
            MSUF_GridFrame:Hide()
            if MSUF_GridFrame.modeHint then
                MSUF_GridFrame.modeHint:Hide()
            end
        end
        return
    end

    if not MSUF_GridFrame then
        MSUF_CreateGridFrame()
    end

    MSUF_GridFrame:Show()
    if MSUF_GridFrame.modeHint then
        MSUF_GridFrame.modeHint:Show()
    end

    -- Info-Text aktualisieren, wenn Grid eingeblendet wird
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end
end
------------------------------------------------------
-- Popup-Fenster für Castbar-Position + Size
-- Style & Verhalten wie MSUF_PositionPopup
------------------------------------------------------
local MSUF_CastbarPositionPopup

function MSUF_OpenCastbarPositionPopup(unit, parent)
    if not MSUF_UnitEditModeActive then
        return
    end
    if not unit or not parent then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        print("|cffffd700MSUF:|r Position/Größe der Castbar kann im Kampf nicht geändert werden.")
        return
    end

    -- Übernimmt die Werte aus dem Castbar-Popup und wendet sie live an
    local function ApplyCastbarPopupValues()
        if InCombatLockdown and InCombatLockdown() then
            print("|cffffd700MSUF:|r Position/Größe der Castbar kann im Kampf nicht geändert werden.")
            return
        end

        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general

        local pf = MSUF_CastbarPositionPopup
        if not pf or not pf.unit or not pf.parent then
            return
        end

        local unit = pf.unit
        local parent = pf.parent

        -- Prefix + Defaults wie in Reanchor-Funktionen
        local prefix
        local defaultX, defaultY

        if unit == "player" then
            prefix = "castbarPlayer"
            defaultX, defaultY = 0, 5
        elseif unit == "target" then
            prefix = "castbarTarget"
            defaultX, defaultY = 65, -15
        elseif unit == "focus" then
            prefix = "castbarFocus"
            defaultX, defaultY = 65, -15
        else
            return
        end

        local currentW = g[prefix .. "BarWidth"]  or g.castbarGlobalWidth  or (parent:GetWidth()  or 200)
        local currentH = g[prefix .. "BarHeight"] or g.castbarGlobalHeight or (parent:GetHeight() or 16)

        local xVal = tonumber(pf.xBox:GetText() or "") or g[prefix .. "OffsetX"] or defaultX
        local yVal = tonumber(pf.yBox:GetText() or "") or g[prefix .. "OffsetY"] or defaultY
        local wVal = tonumber(pf.wBox:GetText() or "") or currentW
        local hVal = tonumber(pf.hBox:GetText() or "") or currentH

        -- einfache Limits, angelehnt an Drag-Logik
        if wVal < 50  then wVal = 50  end
        if wVal > 600 then wVal = 600 end
        if hVal < 8   then hVal = 8   end
        if hVal > 100 then hVal = 100 end

        g[prefix .. "OffsetX"]   = math.floor(xVal + 0.5)
        g[prefix .. "OffsetY"]   = math.floor(yVal + 0.5)
        g[prefix .. "BarWidth"]  = math.floor(wVal + 0.5)
        g[prefix .. "BarHeight"] = math.floor(hVal + 0.5)

        -- Castbar neu verankern / updaten
        if unit == "player" and MSUF_ReanchorPlayerCastBar then
            MSUF_ReanchorPlayerCastBar()
        elseif unit == "target" and MSUF_ReanchorTargetCastBar then
            MSUF_ReanchorTargetCastBar()
        elseif unit == "focus" and MSUF_ReanchorFocusCastBar then
            MSUF_ReanchorFocusCastBar()
        end

        if MSUF_UpdateCastbarVisuals then
            MSUF_UpdateCastbarVisuals()
        end

        if MSUF_UpdateCastbarEditInfo then
            MSUF_UpdateCastbarEditInfo(unit)
        end
        if MSUF_SyncCastbarPositionPopup then
            MSUF_SyncCastbarPositionPopup(unit)
        end
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general


    -- Prefix pro Unit (Player / Target / Focus)
    local prefix
    if unit == "player" then
        prefix = "castbarPlayer"
    elseif unit == "target" then
        prefix = "castbarTarget"
    elseif unit == "focus" then
        prefix = "castbarFocus"
    else
        -- andere Units aktuell nicht unterstützt
        return
    end

    -- Defaults wie in den Reanchor-Funktionen
    local defaultX, defaultY
    if unit == "player" then
        defaultX, defaultY = 0, 5
    else
        defaultX, defaultY = 65, -15
    end

    -- Schutz: völlig abgedrehte Offsets (z.B. 9-stellige Zahlen) wieder
    -- auf einen sinnvollen Bereich zurückholen
    local function SanitizeOffset(v, default)
        v = tonumber(v) or default or 0
        if v > 2000 then
            v = default or 0
        elseif v < -2000 then
            v = default or 0
        end
        -- direkt auf ganze Pixel runden
        return math.floor(v + 0.5)
    end

    local curX = SanitizeOffset(g[prefix .. "OffsetX"], defaultX)
    local curY = SanitizeOffset(g[prefix .. "OffsetY"], defaultY)
    local curW = g[prefix .. "BarWidth"]  or g.castbarGlobalWidth  or (parent:GetWidth()  or 200)
    local curH = g[prefix .. "BarHeight"] or g.castbarGlobalHeight or (parent:GetHeight() or 16)

    -- DB dabei gleich „begradigen“, falls vorher Müll drin war
    g[prefix .. "OffsetX"] = curX
    g[prefix .. "OffsetY"] = curY

    --------------------------------------------------
    -- Frame einmalig erzeugen (Style wie Unitframe-Popup)
    --------------------------------------------------
    if not MSUF_CastbarPositionPopup then
        local pf = CreateFrame("Frame", "MSUF_CastbarPositionPopup", UIParent, "BackdropTemplate")
        MSUF_CastbarPositionPopup = pf

        pf:SetSize(260, 170)
        pf:SetFrameStrata("TOOLTIP")
        pf:SetFrameLevel(130)

        pf:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile     = true,
            tileSize = 32,
            edgeSize = 16,
            insets   = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        pf:SetBackdropColor(0, 0, 0, 0.9)

        -- Bewegbar mit der linken Maustaste (wie Unitframe-Popup)
        pf:SetMovable(true)
        pf:EnableMouse(true)
        pf:RegisterForDrag("LeftButton")
        pf:SetScript("OnDragStart", function(self)
            if self:IsMovable() then
                self:StartMoving()
            end
        end)
        pf:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
        end)

        -- Titel
        local title = pf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -12)
        title:SetText("MSUF Edit – Castbar")
        pf.title = title

        --------------------------------------------------
        -- Labels + EditBoxen (Offset X/Y, Width, Height)
        --------------------------------------------------

        -- Offset X
        local xLabel = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        xLabel:SetPoint("TOPLEFT", pf, "TOPLEFT", 16, -40)
        xLabel:SetText("Offset X:")
        pf.xLabel = xLabel

        local xBox = CreateFrame("EditBox", "$parentXBox", pf, "InputBoxTemplate")
        xBox:SetSize(80, 20)
        xBox:SetPoint("LEFT", xLabel, "RIGHT", 8, 0)
        xBox:SetAutoFocus(false)
        xBox:SetNumeric(false)
        pf.xBox = xBox
        pf.xMinus, pf.xPlus = MSUF_AttachStepperButtons(pf, xBox, ApplyCastbarPopupValues)

        -- Offset Y
        local yLabel = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        yLabel:SetPoint("TOPLEFT", xLabel, "BOTTOMLEFT", 0, -8)
        yLabel:SetText("Offset Y:")
        pf.yLabel = yLabel

        local yBox = CreateFrame("EditBox", "$parentYBox", pf, "InputBoxTemplate")
        yBox:SetSize(80, 20)
        yBox:SetPoint("LEFT", yLabel, "RIGHT", 8, 0)
        yBox:SetAutoFocus(false)
        yBox:SetNumeric(false)
        pf.yBox = yBox
         pf.yMinus, pf.yPlus = MSUF_AttachStepperButtons(pf, yBox, ApplyCastbarPopupValues)

             -- Width
        local wLabel = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        wLabel:SetPoint("TOPLEFT", yLabel, "BOTTOMLEFT", 0, -12)
        wLabel:SetText("Width:")
        pf.wLabel = wLabel

        local wBox = CreateFrame("EditBox", "$parentWBox", pf, "InputBoxTemplate")
        wBox:SetSize(80, 20)
        wBox:SetPoint("LEFT", wLabel, "RIGHT", 8, 0)
        wBox:SetAutoFocus(false)
        wBox:SetNumeric(false)
        pf.wBox = wBox
        pf.wMinus, pf.wPlus = MSUF_AttachStepperButtons(pf, wBox, ApplyCastbarPopupValues)

        -- Height
        local hLabel = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hLabel:SetPoint("TOPLEFT", wLabel, "BOTTOMLEFT", 0, -8)
        hLabel:SetText("Height:")
        pf.hLabel = hLabel

        local hBox = CreateFrame("EditBox", "$parentHBox", pf, "InputBoxTemplate")
        hBox:SetSize(80, 20)
        hBox:SetPoint("LEFT", hLabel, "RIGHT", 8, 0)
        hBox:SetAutoFocus(false)
        hBox:SetNumeric(false)
        pf.hBox = hBox
        pf.hMinus, pf.hPlus = MSUF_AttachStepperButtons(pf, hBox, ApplyCastbarPopupValues)

        -- optionale „Dummy“-Stepper-Handles, falls du sie woanders brauchst
        pf.cbXMinus, pf.cbXPlus = MSUF_AttachStepperButtons(pf, xBox)
        pf.cbYMinus, pf.cbYPlus = MSUF_AttachStepperButtons(pf, yBox)
        pf.cbWMinus, pf.cbWPlus = MSUF_AttachStepperButtons(pf, wBox)
        pf.cbHMinus, pf.cbHPlus = MSUF_AttachStepperButtons(pf, hBox)


        --------------------------------------------------
        -- OK & Cancel Buttons (gleich wie beim Unitframe-Popup)
        --------------------------------------------------
        local okBtn = CreateFrame("Button", "$parentOK", pf, "UIPanelButtonTemplate")
        okBtn:SetSize(70, 22)
        okBtn:SetPoint("BOTTOMRIGHT", -10, 10)
        okBtn:SetText(OKAY)
        pf.okBtn = okBtn

        local cancelBtn = CreateFrame("Button", "$parentCancel", pf, "UIPanelButtonTemplate")
        cancelBtn:SetSize(70, 22)
        cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -6, 0)
        cancelBtn:SetText(CANCEL)
        pf.cancelBtn = cancelBtn

        cancelBtn:SetScript("OnClick", function()
            pf:Hide()
        end)

        -- OK: Werte in die DB schreiben und Castbars neu anwenden
        okBtn:SetScript("OnClick", function()
            ApplyCastbarPopupValues()
            pf:Hide()
        end)


        -- Enter/Escape für alle Editboxen
        local function OnEnterPressed(self)
            okBtn:Click()
        end
        local function OnEscapePressed(self)
            pf:Hide()
        end

        xBox:SetScript("OnEnterPressed", OnEnterPressed)
        yBox:SetScript("OnEnterPressed", OnEnterPressed)
        wBox:SetScript("OnEnterPressed", OnEnterPressed)
        hBox:SetScript("OnEnterPressed", OnEnterPressed)

        xBox:SetScript("OnEscapePressed", OnEscapePressed)
        yBox:SetScript("OnEscapePressed", OnEscapePressed)
        wBox:SetScript("OnEscapePressed", OnEscapePressed)
        hBox:SetScript("OnEscapePressed", OnEscapePressed)
    end

    --------------------------------------------------
    -- Popup mit aktuellen Werten füllen + positionieren
    --------------------------------------------------
    local pf = MSUF_CastbarPositionPopup
    pf.unit   = unit
    pf.parent = parent

    local label = MSUF_GetUnitLabelForKey(GetConfigKeyForUnit(unit)) or unit
    pf.title:SetText(string.format("MSUF Edit – %s Castbar", label))

    pf.xBox:SetText(tostring(curX or 0))
    pf.yBox:SetText(tostring(curY or 0))
    pf.wBox:SetText(tostring(curW or 0))
    pf.hBox:SetText(tostring(curH or 0))

    pf:ClearAllPoints()
    if parent then
        pf:SetPoint("CENTER", parent, "CENTER", 0, 0)
    else
        pf:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    pf:Show()
    pf:Raise()
end

------------------------------------------------------
-- Edit Mode: Update visuals (e.g. player arrows) when toggling
------------------------------------------------------

local function MSUF_UpdateEditModeVisuals()
    if not UnitFrames then return end

    -- Player
    local pf = UnitFrames["player"]
    if pf and pf.UpdateEditArrows then
        pf:UpdateEditArrows()
    end

    -- Target
    local tf = UnitFrames["target"]
    if tf and tf.UpdateEditArrows then
        tf:UpdateEditArrows()
    end

    -- Focus
    local ff = UnitFrames["focus"]
    if ff and ff.UpdateEditArrows then
        ff:UpdateEditArrows()
    end

    -- Pet
    local pet = UnitFrames["pet"]
    if pet and pet.UpdateEditArrows then
        pet:UpdateEditArrows()
    end

    -- Target-of-Target
    local tot = UnitFrames["targettarget"]
    if tot and tot.UpdateEditArrows then
        tot:UpdateEditArrows()
    end

    -- Boss 1–5
    for i = 1, MSUF_MAX_BOSS_FRAMES do
        local bf = UnitFrames["boss" .. i]
        if bf and bf.UpdateEditArrows then
            bf:UpdateEditArrows()
        end
    end

    -- NEU: 20x20px Grid ein-/ausblenden
    MSUF_UpdateGridOverlay()
end


-- Sync helper: update CastbarPositionPopup fields when offsets/size change
local function MSUF_SyncCastbarPositionPopup(unit)
    local pf = MSUF_CastbarPositionPopup
    if not pf or not pf:IsShown() then
        return
    end
    if pf.unit ~= unit then
        return
    end

    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local prefix
    local defaultX, defaultY

    if unit == "player" then
        prefix = "castbarPlayer"
        defaultX, defaultY = 0, 5
    elseif unit == "target" then
        prefix = "castbarTarget"
        defaultX, defaultY = 65, -15
    elseif unit == "focus" then
        prefix = "castbarFocus"
        defaultX, defaultY = 65, -15
    else
        return
    end

    local function SanitizeOffset(v, default)
        v = tonumber(v)
        if not v or math.abs(v) > 10000 then
            return default
        end
        return math.floor(v + 0.5)
    end

    local parent = pf.parent or UIParent
    local curX = SanitizeOffset(g[prefix .. "OffsetX"], defaultX)
    local curY = SanitizeOffset(g[prefix .. "OffsetY"], defaultY)
    local curW = g[prefix .. "BarWidth"]  or g.castbarGlobalWidth  or (parent:GetWidth()  or 200)
    local curH = g[prefix .. "BarHeight"] or g.castbarGlobalHeight or (parent:GetHeight() or 16)

    if pf.xBox and not pf.xBox:HasFocus() then
        pf.xBox:SetText(tostring(curX or 0))
    end
    if pf.yBox and not pf.yBox:HasFocus() then
        pf.yBox:SetText(tostring(curY or 0))
    end
    if pf.wBox and not pf.wBox:HasFocus() then
        pf.wBox:SetText(tostring(curW or 0))
    end
    if pf.hBox and not pf.hBox:HasFocus() then
        pf.hBox:SetText(tostring(curH or 0))
    end
end

------------------------------------------------------
-- Update Blizzard castbar visuals (icon, spell name, font size)
------------------------------------------------------

function MSUF_UpdateCastbarVisuals()
    EnsureDB()
    local g = MSUF_DB.general or {}

    -- Visibility + basic castbar config (from Castbar menu)
    local showIcon    = (g.castbarShowIcon ~= false)
    local showName    = (g.castbarShowSpellName ~= false)
    local fontSize    = tonumber(g.castbarSpellNameFontSize) or 0
    local iconOffsetX = tonumber(g.castbarIconOffsetX) or 0
    local iconOffsetY = tonumber(g.castbarIconOffsetY) or 0

    -- Global font / color / shadow from the Font & Color settings
    local fontPath  = MSUF_GetFontPath()
    local fontFlags = MSUF_GetFontFlags()

    local colorKey  = (g.fontColor or "white"):lower()
    local colorDef  = MSUF_FONT_COLORS[colorKey] or MSUF_FONT_COLORS.white
    local fr, fg, fb = colorDef[1], colorDef[2], colorDef[3]

    local useShadow = g.textBackdrop and true or false

    -- 0 in the castbar font size slider = use the global base font size
    local baseSize      = g.fontSize or 14
    local effectiveSize = (fontSize > 0) and fontSize or baseSize

    --------------------------------------------------
    -- Helper for Blizzard-style castbars
    --------------------------------------------------
    local function ApplyBlizzard(frame)
        if not frame then return end

        local icon = frame.Icon or frame.icon or (frame.IconFrame and frame.IconFrame.Icon)
        if icon then
            icon:SetShown(showIcon)
        end

        local text = frame.Text or frame.text
        if text then
            text:SetShown(showName)

            -- Apply global font + color + shadow to Blizzard castbar text
            text:SetFont(fontPath, effectiveSize, fontFlags)
            text:SetTextColor(fr, fg, fb, 1)

            if useShadow then
                text:SetShadowColor(0, 0, 0, 1)
                text:SetShadowOffset(1, -1)
            else
                text:SetShadowOffset(0, 0)
            end
        end
    end

    -- Blizzard Castbars (Target, Pet etc.)
    ApplyBlizzard(TargetFrameSpellBar)
    ApplyBlizzard(PetCastingBarFrame)

    --------------------------------------------------
    -- Helper for custom MSUF castbars (Zac <3 frames)
    --------------------------------------------------
    local function ApplyMSUF(frame)
        if not frame or not frame.statusBar then
            return
        end

        local statusBar = frame.statusBar
        local icon      = frame.icon

        local width     = frame:GetWidth()  or statusBar:GetWidth()  or 250
        local height    = frame:GetHeight() or statusBar:GetHeight() or 18

        -- Apply global castbar size if configured (same for all MSUF castbars)
        if MSUF_DB and MSUF_DB.general then
            local gg = MSUF_DB.general
            local gw = tonumber(gg.castbarGlobalWidth)
            local gh = tonumber(gg.castbarGlobalHeight)

            if gw and gw > 0 then
                width = gw
                frame:SetWidth(width)
            end
            if gh and gh > 0 then
                height = gh
                frame:SetHeight(gh)
            end
        end

        -- Optional per-frame BAR size overrides (player / target / focus)
        if MSUF_DB and MSUF_DB.general then
            local g2 = MSUF_DB.general

            -- Player bar override
            if frame == MSUF_PlayerCastbar or frame == MSUF_PlayerCastbarPreview then
                local bw = tonumber(g2.castbarPlayerBarWidth)
                local bh = tonumber(g2.castbarPlayerBarHeight)

                if bw and bw > 0 then
                    width = bw
                    frame:SetWidth(width)
                end
                if bh and bh > 0 then
                    height = bh
                    frame:SetHeight(bh)
                end

            -- Target bar override
            elseif frame == MSUF_TargetCastbar or frame == MSUF_TargetCastbarPreview then
                local bw = tonumber(g2.castbarTargetBarWidth)
                local bh = tonumber(g2.castbarTargetBarHeight)

                if bw and bw > 0 then
                    width = bw
                    frame:SetWidth(width)
                end
                if bh and bh > 0 then
                    height = bh
                    frame:SetHeight(bh)
                end

            -- Focus bar override (NEU)
            elseif frame == MSUF_FocusCastbar or frame == MSUF_FocusCastbarPreview then
                local bw = tonumber(g2.castbarFocusBarWidth)
                local bh = tonumber(g2.castbarFocusBarHeight)

                if bw and bw > 0 then
                    width = bw
                    frame:SetWidth(width)
                end
                if bh and bh > 0 then
                    height = bh
                    frame:SetHeight(bh)
                end
            end
        end

        -- Default icon size uses bar height
        local iconWidth  = height
        local iconHeight = height
        
    -- Wenn Icon-Offset genutzt wird, behandeln wir das Icon als "detached"
    local iconDetached = (iconOffsetX ~= 0 or iconOffsetY ~= 0)

    -- Icon handling
    if icon then
        icon:SetShown(showIcon)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", frame, "LEFT", iconOffsetX, iconOffsetY)
        icon:SetSize(iconWidth, iconHeight)
        icon:SetDrawLayer("OVERLAY", 7)
    end

    -- Statusbar geometry
    if statusBar then
        statusBar:ClearAllPoints()
        --Hier wird Icon von der Bar gelöst (Icon lösen)---
        if showIcon and icon and not iconDetached then
            -- Platz für das Icon links lassen
            statusBar:SetPoint("LEFT", frame, "LEFT", iconWidth + 1, 0)
            statusBar:SetWidth(width - (iconWidth + 1))
        else
            -- Ohne Icon volle Breite nutzen
            statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
            statusBar:SetWidth(width)
        end
        statusBar:SetHeight(height - 2)
    end
    -- Hintergrund an die neue Statusbar-Geometrie anpassen
    local backgroundBar = frame.backgroundBar
    if backgroundBar and statusBar then
        backgroundBar:ClearAllPoints()
        backgroundBar:SetAllPoints(statusBar)
    end

        -- Spellname-Text (links)
        local text = frame.castText or frame.Text or frame.text
        if text then
            text:SetShown(showName)

            -- Apply global font + color + shadow to MSUF castbar text
            text:SetFont(fontPath, effectiveSize, fontFlags)
            text:SetTextColor(fr, fg, fb, 1)

            if useShadow then
                text:SetShadowColor(0, 0, 0, 1)
                text:SetShadowOffset(1, -1)
            else
                text:SetShadowOffset(0, 0)
            end
        end

        -- Cast-Timer-Text (rechts) – nur Playerbar hat den
        if frame.timeText then
            frame.timeText:SetFont(fontPath, effectiveSize, fontFlags)
            frame.timeText:SetTextColor(fr, fg, fb, 1)

            if useShadow then
                frame.timeText:SetShadowColor(0, 0, 0, 1)
                frame.timeText:SetShadowOffset(1, -1)
            else
                frame.timeText:SetShadowOffset(0, 0)
            end
        end
    end

    -- Unsere MSUF-Castbars + optional Preview
   ApplyMSUF(MSUF_PlayerCastbar)
    ApplyMSUF(MSUF_TargetCastbar)
    ApplyMSUF(MSUF_FocusCastbar)
    ApplyMSUF(MSUF_PlayerCastbarPreview)
    ApplyMSUF(MSUF_TargetCastbarPreview)
    ApplyMSUF(MSUF_FocusCastbarPreview)
end

local function MSUF_ApplyPlayerCastbarVisibility()
    -- Player castbar is now fully managed by Blizzard. This function is kept as a no-op
    -- so existing calls do nothing and avoid errors.
    return
end






-- Shorten name UTF-8 safe (wirklich!)
local function MSUF_ShortenName(name, maxChars)
    if not name then return "" end

    -- Wenn der Name kurz genug ist, nichts tun
    local len = strlenutf8(name)
    if len <= maxChars then
        return name
    end

    local byteLen   = #name
    local charCount = 0
    local cutPos    = byteLen

    local i = 1
    while i <= byteLen do
        charCount = charCount + 1

        -- Sobald wir über maxChars sind, merken wir uns die Cut-Position
        if charCount > maxChars then
            cutPos = i - 1
            break
        end

        local b = name:byte(i)
        if b <= 0x7F then          -- 1-Byte-Char (ASCII)
            i = i + 1
        elseif b >= 0xC0 and b <= 0xDF then   -- 2-Byte-UTF-8
            i = i + 2
        elseif b >= 0xE0 and b <= 0xEF then   -- 3-Byte-UTF-8
            i = i + 3
        elseif b >= 0xF0 and b <= 0xF7 then   -- 4-Byte-UTF-8
            i = i + 4
        else
            -- Fallback: falls irgendwas Komisches kommt, nur 1 Byte weiter
            i = i + 1
        end
    end

    local truncated = name:sub(1, cutPos)
    return truncated .. "…"
end

------------------------------------------------------
-- SIMPLE TARGET AURAS (BUFFS/DEBUFFS)
------------------------------------------------------
local function MSUF_ShouldShowAura(unit, auraData, filterMode)
    -- Wenn wir gar keine Daten haben, nichts anzeigen
    if not auraData then
        return false
    end

    filterMode = filterMode or "ALL"

    -- "ENEMY" = nur auf feindlichen Zielen anzeigen
    if filterMode == "ENEMY" then
        -- Für Spieler-Ziele trotzdem anzeigen (duell / arena / freundliche Ziele)
        if not UnitIsPlayer(unit) and not UnitCanAttack("player", unit) then
            return false
        end
        return true
    end

    -- "ALL" und "MINE": wir zeigen alles an, ohne auf geheime Felder (secret values) zuzugreifen
    return true
end

local TARGET_AURA_THROTTLE = 0.20
local lastTargetAuraUpdate = 0

function MSUF_UpdateTargetAuras(frame)
    MSUF_ProfileStart("MSUF_UpdateTargetAuras")
    if not frame or frame.unit ~= "target" then
        return
    end

    local unit = frame.unit

    if not UnitExists(unit) then
        if frame.buffIcons then
            for _, iconFrame in ipairs(frame.buffIcons) do
                iconFrame:Hide()
            end
        end
        if frame.debuffIcons then
            for _, iconFrame in ipairs(frame.debuffIcons) do
                iconFrame:Hide()
            end
        end
        return
    end

    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        return
    end

    local now = GetTime()
    if (now - lastTargetAuraUpdate) < TARGET_AURA_THROTTLE then
        MSUF_ProfileStop("MSUF_UpdateTargetAuras")
        return
    end
    lastTargetAuraUpdate = now

    local g = MSUF_DB.general or {}
    local filterMode = g.targetAuraFilter or "ALL"
    local displayMode  = g.targetAuraDisplay or "BUFFS_AND_DEBUFFS"
    local showBuffs    = (displayMode == "BUFFS_ONLY" or displayMode == "BUFFS_AND_DEBUFFS")
    local showDebuffs  = (displayMode == "DEBUFFS_ONLY" or displayMode == "BUFFS_AND_DEBUFFS")

    -- Aura layout settings (width/height/scale/offset relative to target frame)
    local auraWidth   = tonumber(g.targetAuraWidth)
    local auraHeight  = tonumber(g.targetAuraHeight)
    local auraScale   = tonumber(g.targetAuraScale) or 1
    local auraAlpha   = tonumber(g.targetAuraAlpha) or 1
    local auraOffsetX = tonumber(g.targetAuraOffsetX) or 0
    local auraOffsetY = tonumber(g.targetAuraOffsetY) or 2

    -- Clamp aura layout settings to safe ranges
    if auraScale <= 0 then
        auraScale = 1
    end

    if auraAlpha <= 0 or auraAlpha > 1 then
        auraAlpha = 1
    end

    if auraWidth and auraWidth < 0 then auraWidth = nil end
    if auraHeight and auraHeight < 0 then auraHeight = nil end

    local baseWidth  = frame:GetWidth() or 1
    local baseHeight = frame:GetHeight() or 1

    local width  = (auraWidth  and auraWidth  > 0) and auraWidth  or baseWidth
    local height = (auraHeight and auraHeight > 0) and auraHeight or baseHeight

    local iconSize = math.max(14, math.floor(height * 0.7 * auraScale + 0.5))
    local maxPerRow = math.max(1, math.min(12, math.floor(width / (iconSize + 2))))

    frame.buffIcons   = frame.buffIcons   or {}
    frame.debuffIcons = frame.debuffIcons or {}

    local function GetIcon(t, index, parent)
        local iconFrame = t[index]
        if not iconFrame then
            iconFrame = CreateFrame("Frame", nil, parent)
            t[index] = iconFrame
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:SetAlpha(auraAlpha)
            iconFrame:EnableMouse(true)

            local tex = iconFrame:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            iconFrame.icon = tex

            -- Cooldown swipe overlay (Blizzard-style)
            local cd = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
            cd:SetAllPoints(iconFrame)
            cd:SetDrawEdge(false)
            cd:SetReverse(true) -- counter-clockwise, like default auras
            cd.noOCC = true            -- prevent OmniCC double text
            cd.noCooldownCount = true  -- for other cooldown addons
            iconFrame.cooldown = cd

            iconFrame:SetScript("OnEnter", function(self)
            -- Beta-safety: Disable tooltips for MSUF target auras to avoid
            -- Blizzard TooltipDataHandler secret-value (dataInstanceID) errors.
            return
        end)

            iconFrame:SetScript("OnLeave", GameTooltip_Hide)
        else
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:SetAlpha(auraAlpha)

end

        return iconFrame
    end

    -- alte Icons verstecken
    for _, fIcon in ipairs(frame.buffIcons) do
        fIcon:Hide()
    end
    for _, fIcon in ipairs(frame.debuffIcons) do
        fIcon:Hide()
    end

    local function Populate(containerTable, filter, isBuff, rowOffset)
        local shown = 0
        local index = 1
        rowOffset = rowOffset or 0

        while true do
            local auraData = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
            if not auraData then
                break
            end

            if MSUF_ShouldShowAura(unit, auraData, filterMode) then
                shown = shown + 1
                local col = (shown - 1) % maxPerRow
                local row = math.floor((shown - 1) / maxPerRow) + rowOffset

                local iconFrame = GetIcon(containerTable, shown, frame)
                iconFrame.icon:SetTexture(auraData.icon)
                iconFrame.unit           = unit
                iconFrame.auraIndex      = index
                iconFrame.auraFilter     = filter
                iconFrame.isBuff         = isBuff and true or false
                iconFrame.auraInstanceID = auraData.auraInstanceID

                -- Cooldown swipe (uses only duration & expirationTime)
                if iconFrame.cooldown then
                    iconFrame.cooldown:Hide()
                    local duration = auraData.duration
                    local expirationTime = auraData.expirationTime
                    if duration and expirationTime then
                        local ok = pcall(function()
                            local startTime = expirationTime - duration
                            if duration > 0 then
                                iconFrame.cooldown:SetCooldown(startTime, duration)
                            end
                        end)
                        if ok and duration and duration > 0 then
                            iconFrame.cooldown:Show()
                        end
                    end
                end

                iconFrame:ClearAllPoints()
                -- Alle Auren (Buffs & Debuffs) über dem Frame anzeigen (repositionable)
                iconFrame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT",
                    auraOffsetX + col * (iconSize + 2),
                    auraOffsetY + row * (iconSize + 2))

                iconFrame:Show()
            end

            index = index + 1
            if shown >= maxPerRow then
                break
            end
        end

        return shown
    end

    -- Debuffs zuerst (nächste am Frame), Buffs darüber
    local numDebuffs  = 0
    local debuffRows  = 0

    if showDebuffs then
        numDebuffs = Populate(frame.debuffIcons, "HARMFUL", false, 0)
        if numDebuffs > 0 then
            debuffRows = math.floor((numDebuffs - 1) / maxPerRow) + 1
        end
    end

    local buffRowOffset = debuffRows
    if showBuffs then
        Populate(frame.buffIcons,  "HELPFUL", true, buffRowOffset)
    end
    MSUF_ProfileStop("MSUF_UpdateTargetAuras")
end



------------------------------------------------------

------------------------------------------------------
-- PROFILE SYSTEM (GLOBAL + PER CHARACTER)
------------------------------------------------------

local function MSUF_GetCharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

function MSUF_InitProfiles()
    MSUF_GlobalDB = MSUF_GlobalDB or {}
    MSUF_GlobalDB.profiles = MSUF_GlobalDB.profiles or {}
    MSUF_GlobalDB.char = MSUF_GlobalDB.char or {}

    local charKey = MSUF_GetCharKey()
    local char = MSUF_GlobalDB.char[charKey] or {}
    MSUF_GlobalDB.char[charKey] = char

    local active = char.activeProfile

    -- Erste Nutzung des Profil-Systems: bestehende MSUF_DB nach 'Default' migrieren
    if not next(MSUF_GlobalDB.profiles) then
        local base = MSUF_DB or {}
        MSUF_GlobalDB.profiles["Default"] = CopyTable(base)
        if not active then
            active = "Default"
        end
        print("|cff00ff00MSUF:|r Migrated existing settings into profile 'Default'.")
    end

    if not active then
        active = "Default"
    end

    -- Falls das gewünschte Profil nicht existiert, auf ein vorhandenes ausweichen
    if not MSUF_GlobalDB.profiles[active] then
        local fallback
        for _, tbl in pairs(MSUF_GlobalDB.profiles) do
            fallback = tbl
            break
        end
        MSUF_GlobalDB.profiles[active] = CopyTable(fallback or {})
    end

    char.activeProfile = active
    MSUF_ActiveProfile = active
    MSUF_DB = MSUF_GlobalDB.profiles[active]
end

function MSUF_CreateProfile(name)
    if not name or name == "" then return end

    MSUF_GlobalDB = MSUF_GlobalDB or {}
    MSUF_GlobalDB.profiles = MSUF_GlobalDB.profiles or {}

    if MSUF_GlobalDB.profiles[name] then
        print("|cffff0000MSUF:|r Profile '"..name.."' already exists.")
        return
    end

    MSUF_GlobalDB.profiles[name] = CopyTable(MSUF_DB or {})
    print("|cff00ff00MSUF:|r Created new profile '"..name.."'.")
end

function MSUF_SwitchProfile(name)
    if not name or not MSUF_GlobalDB or not MSUF_GlobalDB.profiles or not MSUF_GlobalDB.profiles[name] then
        print("|cffff0000MSUF:|r Unknown profile: "..tostring(name))
        return
    end

    local charKey = MSUF_GetCharKey()
    MSUF_GlobalDB.char = MSUF_GlobalDB.char or {}
    local char = MSUF_GlobalDB.char[charKey] or {}
    MSUF_GlobalDB.char[charKey] = char

    char.activeProfile = name
    MSUF_ActiveProfile = name
    MSUF_DB = MSUF_GlobalDB.profiles[name]

    -- Standardwerte für dieses Profil auffüllen
    if EnsureDB then
        EnsureDB()
    end

    if ApplyAllSettings then
        ApplyAllSettings()
    end
    if UpdateAllFonts then
        UpdateAllFonts()
    end

    print("|cff00ff00MSUF:|r Switched to profile '"..name.."'.")
end

function MSUF_ResetProfile(name)
    name = name or MSUF_ActiveProfile
    if not name or not MSUF_GlobalDB or not MSUF_GlobalDB.profiles or not MSUF_GlobalDB.profiles[name] then
        return
    end

    MSUF_GlobalDB.profiles[name] = {}

    if name == MSUF_ActiveProfile then
        MSUF_DB = MSUF_GlobalDB.profiles[name]
        if EnsureDB then
            EnsureDB()
        end
        if ApplyAllSettings then
            ApplyAllSettings()
        end
        if UpdateAllFonts then
            UpdateAllFonts()
        end
    end

    print("|cffffd700MSUF:|r Profile '"..name.."' reset to defaults.")
end
function MSUF_DeleteProfile(name)
    name = name or MSUF_ActiveProfile

    if not name or not MSUF_GlobalDB or not MSUF_GlobalDB.profiles or not MSUF_GlobalDB.profiles[name] then
        return
    end

    -- Default-Profil nicht löschen, dafür gibt es Reset
    if name == "Default" then
        print("|cffff0000MSUF:|r You cannot delete the 'Default' profile. Use Reset instead.")
        return
    end

    -- Fallback-Profil suchen (irgendein anderes Profil)
    local fallbackName
    for profileName in pairs(MSUF_GlobalDB.profiles) do
        if profileName ~= name then
            fallbackName = fallbackName or profileName
        end
    end

    if not fallbackName then
        print("|cffff0000MSUF:|r Cannot delete the last remaining profile.")
        return
    end

    -- Char-Mappings korrigieren
    if MSUF_GlobalDB.char then
        for _, char in pairs(MSUF_GlobalDB.char) do
            if char.activeProfile == name then
                char.activeProfile = fallbackName
            end
        end
    end

    -- Profil entfernen
    MSUF_GlobalDB.profiles[name] = nil

    -- Falls das aktive Profil gelöscht wurde, auf Fallback wechseln
    if MSUF_ActiveProfile == name then
        MSUF_SwitchProfile(fallbackName)
    end

    print("|cffffd700MSUF:|r Profile '"..name.."' deleted.")
end

function MSUF_GetAllProfiles()
    local list = {}
    if MSUF_GlobalDB and MSUF_GlobalDB.profiles then
        for name in pairs(MSUF_GlobalDB.profiles) do
            table.insert(list, name)
        end
        table.sort(list)
    end
    return list
end

-- NAME COLOR HELPER
------------------------------------------------------
local function MSUF_UpdateNameColor(frame)
    if not frame or not frame.nameText then return end

    EnsureDB()
    local g = MSUF_DB.general

    local r, gCol, b

    -- 1) Klassenfarbe für Spieler, wenn Option aktiv
    if g.nameClassColor and frame.unit and UnitIsPlayer(frame.unit) then
        local _, class = UnitClass(frame.unit)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then
            r, gCol, b = c.r, c.g, c.b
        end
    end

    -- 2) NPC/Boss-Namen nach Reaktion färben, falls Option aktiv
    if (not (r and gCol and b)) and g.npcNameRed and frame.unit and not UnitIsPlayer(frame.unit) then
        local reaction = UnitReaction("player", frame.unit)
        if reaction then
            -- 1-3: feindlich -> rot
            if reaction <= 3 then
                r, gCol, b = 1, 0, 0
            -- 4-8: neutral / freundlich -> weiß
            else
                r, gCol, b = 1, 1, 1
            end
        end
    end

    -- 3) Fallback: globale FontColor
    if not (r and gCol and b) then
        local key   = (g.fontColor or "white"):lower()
        local color = MSUF_FONT_COLORS[key] or MSUF_FONT_COLORS.white
        r, gCol, b  = color[1], color[2], color[3]
    end

    frame.nameText:SetTextColor(r, gCol, b, 1)
end
---------------------------------------------
-- HP GRADIENT HELPER
------------------------------------------------------
local function MSUF_ApplyHPGradient(tex)
    if not tex then return end

    EnsureDB()
    local g = MSUF_DB.general

    local strength = g.gradientStrength or 0.45
    if g.enableGradient == false then
        strength = 0
    end

    -- Sichere Gradient-API für alle Versionen
    if tex.SetGradientAlpha then
        -- ältere API (z.B. 9.x Classic)
        tex:SetGradientAlpha("HORIZONTAL",
            0, 0, 0, 0,          -- links: komplett unsichtbar
            0, 0, 0, strength    -- rechts: leicht abgedunkelt
        )
    elseif tex.SetGradient then
        -- moderne API (Retail 10.0+ / 12.0+)
        tex:SetGradient("HORIZONTAL",
            CreateColor(0, 0, 0, 0),           -- links transparent
            CreateColor(0, 0, 0, strength)     -- rechts Schatten
        )
    else
        -- letzter Fallback (sollte nie passieren)
        tex:SetColorTexture(0, 0, 0, strength)
    end

    if strength > 0 then
        tex:Show()
    else
        tex:Hide()
    end
end
------------------------------------------------------
-- SIMPLE ABSORB OVERLAYS (no secret math)
------------------------------------------------------
local function MSUF_UpdateAbsorbBar(self, unit, maxHP)
    -- Kein Frame / keine Bar / keine API? Raus.
    if not self or not self.absorbBar or not UnitGetTotalAbsorbs then
        return
    end

    EnsureDB()
    local g = MSUF_DB.general or {}

    -- Globale Toggle im Misc-Menü: Absorb-Leiste komplett deaktivieren
    if g.enableAbsorbBar == false then
        self.absorbBar:SetMinMaxValues(0, 1)
        self.absorbBar:SetValue(0)
        self.absorbBar:Hide()
        return
    end

    -- WICHTIG: totalAbs wird NICHT verrechnet, nur durchgereicht.
    local totalAbs = UnitGetTotalAbsorbs(unit)
    if not totalAbs then
        self.absorbBar:SetMinMaxValues(0, 1)
        self.absorbBar:SetValue(0)
        self.absorbBar:Hide()
        return
    end

    local max = maxHP or UnitHealthMax(unit) or 1

    self.absorbBar:SetMinMaxValues(0, max)
    self.absorbBar:SetValue(totalAbs)
    self.absorbBar:Show()
end

local function MSUF_UpdateHealAbsorbBar(self, unit, maxHP)
    -- Heal-Absorb (healing blocked) – eigene API
    if not self or not self.healAbsorbBar or not UnitGetTotalHealAbsorbs then
        return
    end

    local totalHealAbs = UnitGetTotalHealAbsorbs(unit)
    if not totalHealAbs then
        self.healAbsorbBar:SetMinMaxValues(0, 1)
        self.healAbsorbBar:SetValue(0)
        self.healAbsorbBar:Hide()
        return
    end

    local max = maxHP or UnitHealthMax(unit) or 1

    self.healAbsorbBar:SetMinMaxValues(0, max)
    self.healAbsorbBar:SetValue(totalHealAbs)
    self.healAbsorbBar:Show()
end

------------------------------------------------------
-- POSITIONING
------------------------------------------------------
local function PositionUnitFrame(f, unit)
    EnsureDB()
    local key = GetConfigKeyForUnit(unit)
    if not key then return end

    -- WICHTIG:
    -- In Combat dürfen wir keine geschützten Unitframes bewegen
    -- (ClearAllPoints/SetPoint sind dann protected → ADDON_ACTION_BLOCKED).
    if InCombatLockdown() then
        return
    end

    local conf = MSUF_DB[key]
    if not conf then return end

    local anchor = MSUF_GetAnchorFrame()
    f:ClearAllPoints()

    local ecv = _G["EssentialCooldownViewer"]

    if MSUF_DB.general.anchorToCooldown and ecv and anchor == ecv then
        local gapY = conf.offsetY or -20

        if key == "player" then
            f:SetPoint("RIGHT", ecv, "LEFT", -20 + (conf.offsetX or 0), gapY)
            return
        elseif key == "target" then
            f:SetPoint("LEFT", ecv, "RIGHT", 20 + (conf.offsetX or 0), gapY)
            return
        elseif key == "focus" then
            f:SetPoint("TOP", ecv, "LEFT", (conf.offsetX or 0), gapY)
            return
        elseif key == "targettarget" then
            f:SetPoint("TOP", ecv, "RIGHT", (conf.offsetX or 0), gapY - 40)
            return
        end
    end

    if key == "boss" then
        local index = tonumber(unit:match("^boss(%d+)$")) or 1
        local x = conf.offsetX
        local spacing = conf.spacing or -36
        local y = conf.offsetY + (index - 1) * spacing
        f:SetPoint("CENTER", anchor, "CENTER", x, y)
    else
        f:SetPoint("CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
    end
end

------------------------------------------------------
-- APPLY TEXT LAYOUT
------------------------------------------------------
local function ApplyTextLayout(f, conf)
    if not f or not f.textFrame then return end
    local tf = f.textFrame

    local nX = conf.nameOffsetX   or 4
    local nY = conf.nameOffsetY   or -4
    local hX = conf.hpOffsetX     or -4
    local hY = conf.hpOffsetY     or -4
    local pX = conf.powerOffsetX  or -4
    local pY = conf.powerOffsetY  or 4

    if f.nameText then
        f.nameText:ClearAllPoints()
        f.nameText:SetPoint("TOPLEFT", tf, "TOPLEFT", nX, nY)
    end

    if f.hpText then
        f.hpText:ClearAllPoints()
        f.hpText:SetPoint("TOPRIGHT", tf, "TOPRIGHT", hX, hY)
    end

    if f.powerText then
        f.powerText:ClearAllPoints()
        f.powerText:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", pX, pY)
    end
end

------------------------------------------------------
-- UPDATE LOGIC
------------------------------------------------------
local FRAME_UPDATE_THROTTLE = 0.05
local MSUF_LastUnitUpdate = {}

function UpdateSimpleUnitFrame(self)
    MSUF_ProfileStart("UpdateSimpleUnitFrame")

    local unit   = self.unit
    local exists = UnitExists(unit)

    -- Respect per-frame enable flags
    local key  = GetConfigKeyForUnit(unit)
    local conf = key and MSUF_DB[key]
    if conf and conf.enabled == false then
        if not InCombatLockdown() then
            self:Hide()

            -- Ensure focus castbar stays attached even during combat updates
            if self.unit == "focus" and MSUF_ReanchorFocusCastBar then
                MSUF_ReanchorFocusCastBar()
            end
        end

        -- Clear bars/texts
        if self.hpBar then
            self.hpBar:SetMinMaxValues(0, 1)
            self.hpBar:SetValue(0)
        end

        if self.absorbBar then
            self.absorbBar:SetMinMaxValues(0, 1)
            self.absorbBar:SetValue(0)
            self.absorbBar:Hide()
        end

        if self.healAbsorbBar then
            self.healAbsorbBar:SetMinMaxValues(0, 1)
            self.healAbsorbBar:SetValue(0)
            self.healAbsorbBar:Hide()
        end

        if self.nameText  then self.nameText:SetText("")  end
        if self.hpText    then self.hpText:SetText("")    end
        if self.powerText then
            self.powerText:SetText("")
            self.powerText:Hide()
        end
        if self.leaderIcon then
            self.leaderIcon:Hide()
        end
        return
    end

    -- Boss test mode: fake data for boss frames when enabled
    if self.isBoss and MSUF_BossTestMode then
        -- Out of combat dürfen wir sicher Show/Alpha setzen → Preview sichtbar
        if not InCombatLockdown() then
            self:Show()
            self:SetAlpha(1)
        end

        -- Fake-HP-Balken (mit derselben Farb-Logik wie im echten Boss-Frame)
              if self.bg then
            local darkMode      = MSUF_DB.general and MSUF_DB.general.darkMode
            local useClassColor = MSUF_DB.general and MSUF_DB.general.useClassColors

            if darkMode or useClassColor then
                -- Dark Mode + Class Color: beide nutzen den Brightness-Slider
                local bgBrightness = 0.25
                if MSUF_DB and MSUF_DB.general and MSUF_DB.general.darkBgBrightness then
                    bgBrightness = MSUF_DB.general.darkBgBrightness
                end
                self.bg:SetColorTexture(bgBrightness, bgBrightness, bgBrightness, 0.9)
            else
                -- Standard-Grau für alle anderen Fälle
                self.bg:SetColorTexture(0.4, 0.4, 0.4, 0.9)
            end
        end

        -- Hintergrund abhängig vom Bar-Mode (Dark / ClassColor / Default)
               if self.bg then
            local darkMode      = MSUF_DB.general and MSUF_DB.general.darkMode
            local useClassColor = MSUF_DB.general and MSUF_DB.general.useClassColors

            if darkMode or useClassColor then
                -- Dark Mode + Class Color: beide nutzen den Brightness-Slider
                local bgBrightness = 0.25
                if MSUF_DB and MSUF_DB.general and MSUF_DB.general.darkBgBrightness then
                    bgBrightness = MSUF_DB.general.darkBgBrightness
                end
                self.bg:SetColorTexture(bgBrightness, bgBrightness, bgBrightness, 0.9)
            else
                -- Standard-Grau für alle anderen Fälle
                self.bg:SetColorTexture(0.4, 0.4, 0.4, 0.9)
            end
        end


        -- kleine Power-Bar unter dem Boss (nur wenn in den Bars aktiviert)
        if self.targetPowerBar then
                        if MSUF_DB.bars and MSUF_DB.bars.showTargetPowerBar == false then
                self.targetPowerBar:Hide()
            else
                self.targetPowerBar:SetMinMaxValues(0, 100)
                self.targetPowerBar:SetValue(40)
                self.targetPowerBar:SetStatusBarColor(0.6, 0.2, 1.0)
                self.targetPowerBar:Show()
            end
        end

        -- Name: "Test Boss 1–5"
        if self.nameText then
            if self.showName ~= false then
                local idx
                if type(unit) == "string" then
                    idx = unit:match("boss(%d+)")
                end
                if idx then
                    self.nameText:SetText("Test Boss " .. idx)
                else
                    self.nameText:SetText("Test Boss")
                end
                self.nameText:Show()
            else
                self.nameText:SetText("")
                self.nameText:Hide()
            end
        end

        -- HP-Text
        if self.hpText then
            if self.showHPText ~= false then
                self.hpText:SetText("75 / 100")
                self.hpText:Show()
            else
                self.hpText:SetText("")
                self.hpText:Hide()
            end
        end

        -- Power-Text (Resource) im Preview: respektiert die Show-Resource-Einstellung
        if self.powerText then
            local showPower = self.showPowerText
            if showPower == nil then
                showPower = true
            end

            if showPower then
                -- Beispielwerte für Mana/Energie im Preview
                self.powerText:SetText("40 / 100")
                self.powerText:Show()
            else
                self.powerText:SetText("")
                self.powerText:Hide()
            end
        end

        return
    end

    --------------------------------------------------
    -- BOSS FRAMES
    --------------------------------------------------
    if self.isBoss then
        if not exists then
            -- In combat we cannot safely Hide()/Show() secure boss frames.
            -- Instead, keep the frame shown but fully transparent and clear all texts.
            self:SetAlpha(0)
            if self.hpBar then
                self.hpBar:SetMinMaxValues(0, 1)
                self.hpBar:SetValue(0)
            end
            if self.nameText  then self.nameText:SetText("")  end
            if self.hpText    then self.hpText:SetText("")    end
            if self.powerText then
                self.powerText:SetText("")
                self.powerText:Hide()
            end
            return
        else
            -- Boss unit exists: fade the frame in (allowed in combat).
            self:SetAlpha(1)
        end
    end

    -- NO UNIT (Target/Focus)
    --------------------------------------------------
    if not exists then
        -- For target/focus/ToT we also avoid Hide()/Show() in combat.
        -- We simply fade the frame out and clear all values/texts so that
        -- no black background or border is left behind.
        if unit ~= "player" then
            self:SetAlpha(0)
        end
        if self.hpBar then
            self.hpBar:SetMinMaxValues(0, 1)
            self.hpBar:SetValue(0)
        end

        if self.absorbBar then
            self.absorbBar:SetMinMaxValues(0, 1)
            self.absorbBar:SetValue(0)
            self.absorbBar:Hide()
        end

        if self.healAbsorbBar then
            self.healAbsorbBar:SetMinMaxValues(0, 1)
            self.healAbsorbBar:SetValue(0)
            self.healAbsorbBar:Hide()
        end

        if self.nameText  then self.nameText:SetText("")  end
        if self.hpText    then self.hpText:SetText("")    end
        if self.powerText then
            self.powerText:SetText("")
            self.powerText:Hide()
        end
        return
    else
        if unit ~= "player" then
            self:SetAlpha(1)
        end
    end

    --------------------------------------------------
    -- HP BAR VALUE
    --------------------------------------------------
    local maxHP = UnitHealthMax(unit)
    if maxHP then
        self.hpBar:SetMinMaxValues(0, maxHP)
    end

    local hp = UnitHealth(unit)
    if hp then
        self.hpBar:SetValue(hp)
    end

    -- Damage-Absorb (Disc-Bubble etc.)
    if self.absorbBar then
        MSUF_UpdateAbsorbBar(self, unit, maxHP)
    end

    -- Heal-Absorb (Heilung blockiert)
    if self.healAbsorbBar then
        MSUF_UpdateHealAbsorbBar(self, unit, maxHP)
    end

    --------------------------------------------------
    -- BAR COLOR (Dark / Class Color + NPC red/black)
    --------------------------------------------------
    local darkMode      = MSUF_DB.general.darkMode
    local useClassColor = MSUF_DB.general.useClassColors

    -- konfigurierbare Dark-Mode-Farbe
    local darkR, darkG, darkB = 0, 0, 0
    local toneKey = MSUF_DB.general.darkBarTone or "black"
    local tone = MSUF_DARK_TONES and MSUF_DARK_TONES[toneKey]
    if tone then
        darkR, darkG, darkB = tone[1], tone[2], tone[3]
    end

    local barR, barG, barB
    local isPlayerUnit = UnitIsPlayer(unit)

    if darkMode then
        -- Dark Mode gewinnt immer: alle Bars dunkel
        barR, barG, barB = darkR, darkG, darkB
    elseif useClassColor then
        if isPlayerUnit then
            -- Spieler in Klassenfarbe
            local _, class = UnitClass(unit)
            local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if color then
                barR, barG, barB = color.r, color.g, color.b
            else
                barR, barG, barB = 0, 1, 0
            end
      else
            -- NPCs: Farbe nach Reaktion (freundlich/neutral/feindlich)
            local reaction = UnitReaction(unit, "player")

            if reaction and reaction >= 5 then
                -- freundlich (freundlich / geehrt / ehrfürchtig usw.)
                barR, barG, barB = 0, 1, 0            -- grün
            elseif reaction == 4 then
                -- neutral
                barR, barG, barB = 1, 1, 0            -- gelb
            else
                -- feindlich / unbekannt
                barR, barG, barB = 0.85, 0.10, 0.10   -- rot
            end
        end
    else
        -- Standard: grün
        barR, barG, barB = 0, 1, 0
    end

    self.hpBar:SetStatusBarColor(barR, barG, barB, 1)

    if self.hpGradient then
        MSUF_ApplyHPGradient(self.hpGradient)
    end

    if self.bg then
        -- Slider steuert jetzt Dark Mode UND Class Color
        if darkMode or useClassColor then
            local bgBrightness = 0.25
            if MSUF_DB and MSUF_DB.general and MSUF_DB.general.darkBgBrightness then
                bgBrightness = MSUF_DB.general.darkBgBrightness
            end
            self.bg:SetColorTexture(bgBrightness, bgBrightness, bgBrightness, 0.9)
        else
            -- Standard: grauer Rahmen
            self.bg:SetColorTexture(0.4, 0.4, 0.4, 0.9)
        end
    end


        --------------------------------------------------
    -- BAR BORDER
    --------------------------------------------------
    local borderEnabled = true

    -- Globale Einstellung (General-Tab), rückwärtskompatibel
    if MSUF_DB and MSUF_DB.general then
        borderEnabled = (MSUF_DB.general.useBarBorder ~= false)
    end

    -- Bars-Tab: "Show bar border" CheckBox überschreibt globalen Wert
    if MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.showBarBorder ~= nil then
        borderEnabled = (MSUF_DB.bars.showBarBorder ~= false)
    end

    if borderEnabled then
        if not self.border then
            self.border = CreateFrame("Frame", nil, self, BackdropTemplateMixin and "BackdropTemplate")
        end

        local style = MSUF_DB.general.barBorderStyle or "THIN"

        if style == "THIN" then
            self.border:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 10,
            })
            self.border:SetBackdropBorderColor(0, 0, 0, 1)
        elseif style == "THICK" then
            self.border:SetBackdrop({
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                edgeSize = 16,
            })
            self.border:SetBackdropBorderColor(0, 0, 0, 1)
        elseif style == "SHADOW" then
            self.border:SetBackdrop({
                edgeFile = "Interface\\GLUES\\COMMON\\TextPanel-Border",
                edgeSize = 14,
            })
            self.border:SetBackdropBorderColor(0, 0, 0, 0.9)
elseif style == "GLOW" then
    self.border:SetBackdrop({
        edgeFile = MSUF_TEX_WHITE8,
        edgeSize = 8,
    })
            self.border:SetBackdropBorderColor(1, 1, 1, 0.6)
        else
            -- fallback
            self.border:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 10,
            })
            self.border:SetBackdropBorderColor(0, 0, 0, 1)
        end

        self.border:SetPoint("TOPLEFT", self.hpBar, "TOPLEFT", -2, 2)
        self.border:SetPoint("BOTTOMRIGHT", self.hpBar, "BOTTOMRIGHT", 2, -2)
        self.border:Show()
    else
        if self.border then
            self.border:Hide()
        end
    end
    --------------------------------------------------
      --------------------------------------------------
    -- NAME (Text + Farbupdate)
    --------------------------------------------------
    local name = UnitName(unit)
    if self.showName ~= false and name then
        -- optional: shorten names globally if the option is enabled
        if MSUF_DB and MSUF_DB.shortenNames then
            name = MSUF_ShortenName(name, 12)
        end
        self.nameText:SetText(name)
    else
        self.nameText:SetText("")
    end

    MSUF_UpdateNameColor(self)

    --------------------------------------------------
    -- GROUP LEADER ICON (player/target)
    --------------------------------------------------
    if self.leaderIcon then
        EnsureDB()
        local g = MSUF_DB.general or {}
        if g.showLeaderIcon == false then
            -- Global toggle disabled: never show leader icon
            self.leaderIcon:Hide()
        else
            if UnitIsGroupLeader and UnitIsGroupLeader(unit) then
                self.leaderIcon:Show()
            else
                self.leaderIcon:Hide()
            end
        end
    end

---------------------------------------------------
-- HP TEXT (abgekürzt + konfigurierbarer Modus + optionaler Absorb-Rohwert)
--------------------------------------------------
if self.showHPText ~= false and hp then
    local hpStr = AbbreviateLargeNumbers(hp)
    -- Verwende UnitHealthPercent mit scaleTo100=true, damit wir 0–100 bekommen
    local hpPct = UnitHealthPercent and UnitHealthPercent(unit, false, true)

    local g = MSUF_DB.general or {}
    local hpMode = g.hpTextMode or "FULL_PLUS_PERCENT"

    --------------------------------------------------
    -- Optional: Total Absorb-Rohwert anzeigen
    -- WICHTIG: UnitGetTotalAbsorbs-Wert wird nur als Text genutzt,
    --         KEINE Vergleiche / Rechnungen mit dem Secret-Value!
    --------------------------------------------------
    local absorbSuffix = ""
    if g.showTotalAbsorbAmount and UnitGetTotalAbsorbs then
        local absorbValue = UnitGetTotalAbsorbs(unit)
        absorbSuffix = " (+" .. tostring(absorbValue) .. ")"
    end

    if hpPct ~= nil then
        if hpMode == "FULL_ONLY" then
            -- Nur absoluter HP-Wert (z.B. "142k (+35000)")
            self.hpText:SetText((hpStr or "") .. absorbSuffix)
        elseif hpMode == "PERCENT_ONLY" then
            -- Nur Prozent (z.B. "64% (+35000)")
            self.hpText:SetFormattedText("%d%%%s", hpPct, absorbSuffix)
        else
            -- Absolut + Prozent (z.B. "142k 64% (+35000)")
            self.hpText:SetFormattedText("%s %d%%%s", hpStr or "", hpPct, absorbSuffix)
        end
    else
        -- Wenn wir keinen Prozentwert bekommen, fallback auf absoluten Wert
        self.hpText:SetText((hpStr or "") .. absorbSuffix)
    end
else
    self.hpText:SetText("")
end

--------------------------------------------------
-- POWER TEXT (Player/Focus/Boss/Spieler-Targets)
    --------------------------------------------------
    local showPower = self.showPowerText
    if showPower == nil then
        showPower = true
    end

    if showPower then
        if unit == "player" or unit == "focus" or self.isBoss or UnitIsPlayer(unit) then
            local p    = UnitPower(unit) or 0
            local pMax = UnitPowerMax(unit) or 0
            self.powerText:SetFormattedText("%d / %d", p, pMax)
            self.powerText:Show()
        else
            self.powerText:SetText("")
            self.powerText:Hide()
        end
    else
        self.powerText:SetText("")
        self.powerText:Hide()
    end

    --------------------------------------------------
    -- SMALL POWER BAR UNDER PLAYER / FOCUS / TARGET / BOSSES (SIMPLE VERSION)
    --------------------------------------------------
    local isTargetLike = (unit == "player" or unit == "focus" or unit == "target" or self.isBoss)

    if self.targetPowerBar and isTargetLike then
        EnsureDB()
        local barsConf = MSUF_DB.bars or {}

        local hideForUnit = false
        if unit == "player" then
            if barsConf.showPlayerPowerBar == false then
                hideForUnit = true
            end
        elseif unit == "focus" then
            if barsConf.showFocusPowerBar == false then
                hideForUnit = true
            end
        elseif unit == "target" then
            if barsConf.showTargetPowerBar == false then
                hideForUnit = true
            end
        elseif self.isBoss then
            if barsConf.showBossPowerBar == false then
                hideForUnit = true
            end
        end

        if hideForUnit then
            self.targetPowerBar:SetScript("OnUpdate", nil)
            self.targetPowerBar:Hide()
        else
            local pType = UnitPowerType(unit)
            local cur   = UnitPower(unit, pType)
            local max   = UnitPowerMax(unit, pType)

            if max ~= nil and cur ~= nil then
                local col = PowerBarColor[pType] or { r = 0.8, g = 0.8, b = 0.8 }
                self.targetPowerBar:SetStatusBarColor(col.r, col.g, col.b)

                -- Wichtig: wir benutzen den Wert direkt ohne arithmetische Operationen.
                -- SetMinMaxValues und SetValue können damit umgehen.
                self.targetPowerBar:SetMinMaxValues(0, max)
                self.targetPowerBar:SetScript("OnUpdate", nil)
                self.targetPowerBar:SetValue(cur)
                self.targetPowerBar:Show()
            else
                self.targetPowerBar:SetScript("OnUpdate", nil)
                self.targetPowerBar:Hide()
            end
        end
    elseif self.targetPowerBar and not isTargetLike then
        self.targetPowerBar:SetScript("OnUpdate", nil)
        self.targetPowerBar:Hide()
    end

    -- Keep castbars in sync with MSUF frames
    MSUF_ProfileStop("UpdateSimpleUnitFrame")
end

------------------------------------------------------
-- APPLY SETTINGS TO FRAMES
------------------------------------------------------
local function ApplySettingsForKey(key)
    EnsureDB()
    local conf = MSUF_DB[key]
    if not conf then return end

    -- if frame is disabled in config, hide and skip
    local function hideFrame(unit)
        local f = UnitFrames[unit]
        if f then
            f:Hide()
        end
    end

    if conf.enabled == false then
        if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "pet" then
            hideFrame(key)
        elseif key == "boss" then
            for i = 1, MSUF_MAX_BOSS_FRAMES do
                hideFrame("boss" .. i)
            end
        end
        return
    end

    local function applyToFrame(unit)
        local f = UnitFrames[unit]
        if not f then return end

        f:SetSize(conf.width, conf.height)
        f.showName      = conf.showName
        f.showHPText    = conf.showHP
        f.showPowerText = conf.showPower
        f:Show()

        PositionUnitFrame(f, unit)
        ApplyTextLayout(f, conf)
        UpdateSimpleUnitFrame(f)
    end

    if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "pet" then
        applyToFrame(key)
    elseif key == "boss" then
        for i = 1, MSUF_MAX_BOSS_FRAMES do
            applyToFrame("boss" .. i)
        end
    end

    -- NEU: nach Größenänderung die Castbars sofort neu ausrichten
    if key == "player" and MSUF_ReanchorPlayerCastBar then
        MSUF_ReanchorPlayerCastBar()
    elseif key == "target" and MSUF_ReanchorTargetCastBar then
        MSUF_ReanchorTargetCastBar()
    elseif key == "focus" and MSUF_ReanchorFocusCastBar then
        MSUF_ReanchorFocusCastBar()
    end
end

function ApplyAllSettings()
    ApplySettingsForKey("player")
    ApplySettingsForKey("target")
    ApplySettingsForKey("focus")
    ApplySettingsForKey("targettarget")
    ApplySettingsForKey("pet")
    ApplySettingsForKey("boss")

    -- after changing settings, also refresh fonts and bar textures
    if UpdateAllFonts then
        UpdateAllFonts()
    end
    if UpdateAllBarTextures then
        UpdateAllBarTextures()
    end
    if MSUF_UpdateCastbarTextures then
        MSUF_UpdateCastbarTextures()
    end
    if MSUF_UpdateCastbarVisuals then
        MSUF_UpdateCastbarVisuals()
    end
end


------------------------------------------------------
-- UPDATE ALL FONTS (z.B. bei Fontwechsel/Bold)
------------------------------------------------------

------------------------------------------------------
-- UPDATE ALL HIGHLIGHT COLORS
------------------------------------------------------
local function UpdateAllHighlightColors()
    EnsureDB()
    if not UnitFrames then return end

    local g = MSUF_DB.general or {}
    local enabled = (g.highlightEnabled ~= false)

    for _, f in pairs(UnitFrames) do
        if f.highlightBorder then
            if not enabled then
                f.highlightBorder:Hide()
            elseif f.UpdateHighlightColor then
                f:UpdateHighlightColor()
            end
        elseif f.UpdateHighlightColor and enabled then
            -- Fallback: falls kein highlightBorder gesetzt ist
            f:UpdateHighlightColor()
        end
    end
end

local function UpdateAllFonts()
    local path  = MSUF_GetFontPath()
    local flags = MSUF_GetFontFlags()

    EnsureDB()
    local g = MSUF_DB.general

    -- globale Font-Farbe aus dem Dropdown
    local key   = (g.fontColor or "white"):lower()
    local color = MSUF_FONT_COLORS[key] or MSUF_FONT_COLORS.white
    local fr, fg, fb = color[1], color[2], color[3]

    -- globale Fontgröße + optionale Spezialisierungen
    local baseSize    = g.fontSize or 14
    local nameSize    = g.nameFontSize  or baseSize
    local hpSize      = g.hpFontSize    or baseSize
    local powerSize   = g.powerFontSize or baseSize

    local useShadow = g.textBackdrop and true or false

    for _, f in pairs(UnitFrames) do
        --------------------------------------------------
        -- NAME: Font immer, Farbe je nach Option
        --------------------------------------------------
        if f.nameText then
            f.nameText:SetFont(path, nameSize, flags)
            MSUF_UpdateNameColor(f)
            if useShadow then
                f.nameText:SetShadowColor(0, 0, 0, 1)
                f.nameText:SetShadowOffset(1, -1)
            else
                f.nameText:SetShadowOffset(0, 0)
            end
        end

        --------------------------------------------------
        -- HP-TEXT: immer FontColor
        --------------------------------------------------
        if f.hpText then
            f.hpText:SetFont(path, hpSize, flags)
            f.hpText:SetTextColor(fr, fg, fb, 1)
            if useShadow then
                f.hpText:SetShadowColor(0, 0, 0, 1)
                f.hpText:SetShadowOffset(1, -1)
            else
                f.hpText:SetShadowOffset(0, 0)
            end
        end

        --------------------------------------------------
        -- RESOURCE-TEXT: immer FontColor
        --------------------------------------------------
        if f.powerText then
            f.powerText:SetFont(path, powerSize, flags)
            f.powerText:SetTextColor(fr, fg, fb, 1)
            if useShadow then
                f.powerText:SetShadowColor(0, 0, 0, 1)
                f.powerText:SetShadowOffset(1, -1)
            else
                f.powerText:SetShadowOffset(0, 0)
            end
        end
    end

    -- Also update castbar text (font, color, shadow) to follow global font settings
    MSUF_UpdateCastbarVisuals()
end
--------------
-- UPDATE ALL BAR TEXTURES (e.g. after SharedMedia change)
------------------------------------------------------
local function UpdateAllBarTextures()
    local tex = MSUF_GetBarTexture()
    if not tex then return end

    for _, f in pairs(UnitFrames) do
        if f.hpBar then
            f.hpBar:SetStatusBarTexture(tex)
        end
        if f.absorbBar then
            f.absorbBar:SetStatusBarTexture(tex)
        end
        if f.healAbsorbBar then
            f.healAbsorbBar:SetStatusBarTexture(tex)
        end
    end
end

------------------------------------------------------
-- CREATE UNITFRAME
------------------------------------------------------

local function MSUF_NudgeUnitFrameOffset(unit, parent, deltaX, deltaY)
    if not unit or not parent then return end
    EnsureDB()

    local key  = GetConfigKeyForUnit(unit)
    local conf = key and MSUF_DB[key]
    if not conf then return end

    -- Immer 1 Pixel pro Klick
    local STEP = 1
    deltaX = (deltaX or 0) * STEP
    deltaY = (deltaY or 0) * STEP

    if MSUF_EditModeSizing then
        -- Sizing Mode: X/Y-Pfeile ändern Breite/Höhe
        local w = conf.width  or parent:GetWidth()  or 250
        local h = conf.height or parent:GetHeight() or 40

        w = w + deltaX
        h = h + deltaY

        -- Hard-Limits, damit Frames nicht verschwinden
        if w < 80  then w = 80  end
        if w > 600 then w = 600 end
        if h < 20  then h = 20  end
        if h > 220 then h = 220 end

        conf.width  = w
        conf.height = h

        if key == "boss" then
            -- Boss-Gruppe: immer alle 5 Frames gemeinsam skalieren
            for i = 1, MSUF_MAX_BOSS_FRAMES do
                local bossUnit = "boss" .. i
                local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                if frame then
                    frame:SetSize(w, h)
                    if UpdateSimpleUnitFrame then
                        UpdateSimpleUnitFrame(frame)
                    end
                end
            end
        else
            parent:SetSize(w, h)
            if UpdateSimpleUnitFrame then
                UpdateSimpleUnitFrame(parent)
            end
        end
    else
        -- Position Mode: Pfeile verschieben das Frame
        conf.offsetX = (conf.offsetX or 0) + deltaX
        conf.offsetY = (conf.offsetY or 0) + deltaY

        -- Frame neu positionieren
        if key == "boss" then
            -- Boss-Gruppe: immer alle 5 Frames gemeinsam bewegen
            for i = 1, MSUF_MAX_BOSS_FRAMES do
                local bossUnit = "boss" .. i
                local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                if frame then
                    PositionUnitFrame(frame, bossUnit)
                end
            end
        else
            PositionUnitFrame(parent, unit)
        end

        -- Falls der entsprechende Tab im Optionsmenü offen ist, Slider syncen
        if MSUF_CurrentOptionsKey == key then
            local xSlider = _G["MSUF_OffsetXSlider"]
            local ySlider = _G["MSUF_OffsetYSlider"]
            if xSlider and xSlider.SetValue then
                xSlider:SetValue(conf.offsetX or 0)
            end
            if ySlider and ySlider.SetValue then
                ySlider:SetValue(conf.offsetY or 0)
            end
        end
    end

    -- Info-Text aktualisieren
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end
end


local function MSUF_SyncUnitPositionPopup(unit, conf)
    local pf = MSUF_PositionPopup
    if not pf or not pf:IsShown() then
        return
    end
    if pf.unit ~= unit then
        return
    end

    local x = conf.offsetX or 0
    local y = conf.offsetY or 0
    local w = conf.width
    local h = conf.height

    -- Falls Width/Height noch nicht in der DB stehen, nimm die Parent-Size
    if (not w or not h) and pf.parent then
        w = w or pf.parent:GetWidth()
        h = h or pf.parent:GetHeight()
    end

    if pf.xBox and not pf.xBox:HasFocus() then
        pf.xBox:SetText(tostring(math.floor(x + 0.5)))
    end
    if pf.yBox and not pf.yBox:HasFocus() then
        pf.yBox:SetText(tostring(math.floor(y + 0.5)))
    end
    if pf.wBox and not pf.wBox:HasFocus() and w then
        pf.wBox:SetText(tostring(math.floor(w + 0.5)))
    end
    if pf.hBox and not pf.hBox:HasFocus() and h then
        pf.hBox:SetText(tostring(math.floor(h + 0.5)))
    end
end

local function MSUF_EnableUnitFrameDrag(f, unit)
    if not f or not unit then return end

    f:EnableMouse(true)

        f:SetScript("OnMouseDown", function(self, button)
        ----------------------------------------------------------------
        -- Rechtsklick: X/Y-Popup für dieses MSUF-Frame öffnen
        ----------------------------------------------------------------
        if button == "RightButton" then
            -- Nur, wenn unser interner Edit Mode an ist
            if not MSUF_UnitEditModeActive then return end
            -- Nicht im Kampf
            if InCombatLockdown and InCombatLockdown() then return end

            -- Nur im Positionsmodus (Size-Mode lassen wir erstmal außen vor)
            if not MSUF_EditModeSizing and MSUF_OpenPositionPopup then
                MSUF_OpenPositionPopup(unit, self)
            end
            return
        end

        ----------------------------------------------------------------
        -- Links-Klick: wie bisher Draggen (Position / ggf. Size)
        ----------------------------------------------------------------
        -- Nur linker Mausklick
        if button ~= "LeftButton" then return end
        -- Nur wenn internes MSUF-Edit-Mode aktiv
        if not MSUF_UnitEditModeActive then return end
        -- Nicht im Kampf verschieben
        if InCombatLockdown and InCombatLockdown() then return end

        EnsureDB()
        local key  = GetConfigKeyForUnit(unit)
        local conf = key and MSUF_DB[key]
        if not conf then return end
        
        -- Dieses Frame ist jetzt das aktive Edit-Target
        MSUF_CurrentEditUnitKey = key
        if MSUF_UpdateEditModeInfo then
            MSUF_UpdateEditModeInfo()
        end

        self.isDragging = true

        local uiScale = UIParent:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        cx, cy = cx / uiScale, cy / uiScale

        self.dragStartCursorX = cx
        self.dragStartCursorY = cy
        self.dragStartOffsetX = conf.offsetX or 0
        self.dragStartOffsetY = conf.offsetY or 0
        self.dragStartWidth   = conf.width  or (self:GetWidth() or 250)
        self.dragStartHeight  = conf.height or (self:GetHeight() or 40)

        self:SetScript("OnUpdate", function(self, elapsed)
            if not self.isDragging then
                self:SetScript("OnUpdate", nil)
                return
            end

            -- Falls während des Draggen Kampf beginnt → abbrechen
            if InCombatLockdown and InCombatLockdown() then
                self.isDragging = false
                self:SetScript("OnUpdate", nil)
                return
            end

            local uiScale = UIParent:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            cx, cy = cx / uiScale, cy / uiScale

            local dx = cx - (self.dragStartCursorX or cx)
            local dy = cy - (self.dragStartCursorY or cy)

            EnsureDB()
            local key2  = GetConfigKeyForUnit(unit)
            local conf2 = key2 and MSUF_DB[key2]
            if not conf2 then return end

            if MSUF_EditModeSizing then
                --------------------------------------------------
                -- SIZING MODE: Drag ändert Breite/Höhe des Frames
                --------------------------------------------------
                local newW = (self.dragStartWidth or conf2.width or (self:GetWidth() or 250)) + dx
                local newH = (self.dragStartHeight or conf2.height or (self:GetHeight() or 40)) + dy

                -- Limits
                if newW < 80  then newW = 80  end
                if newW > 600 then newW = 600 end
                if newH < 20  then newH = 20  end
                if newH > 600 then newH = 600 end

                conf2.width  = newW
                conf2.height = newH
                MSUF_SyncUnitPositionPopup(unit, conf2)

                if key2 == "boss" then
                    -- Boss-Gruppe: immer alle 5 Frames gemeinsam skalieren
                    for i = 1, MSUF_MAX_BOSS_FRAMES do
                        local bossUnit = "boss" .. i
                        local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                        if frame then
                            frame:SetSize(newW, newH)
                            if UpdateSimpleUnitFrame then
                                UpdateSimpleUnitFrame(frame)
                            end
                        end
                    end
                else
                    local frame = (UnitFrames and UnitFrames[unit]) or self
                    frame:SetSize(newW, newH)
                    if UpdateSimpleUnitFrame then
                        UpdateSimpleUnitFrame(frame)
                    end
                end

            else
                --------------------------------------------------
                -- POSITION MODE: Drag verschiebt das Frame (X/Y)
                --------------------------------------------------
                local newX = (self.dragStartOffsetX or 0) + dx
                local newY = (self.dragStartOffsetY or 0) + dy

                -- Optional: Snap-to-Grid wie im Blizzard Edit Mode
                local g = MSUF_DB and MSUF_DB.general or nil
                if g and g.editModeSnapToGrid then
                    local gridStep = g.editModeGridStep or 20 -- dein Grid-Slider, sonst 20px
                    if gridStep < 1 then
                        gridStep = 1
                    end
                    local half = gridStep / 2
                    newX = math.floor((newX + half) / gridStep) * gridStep
                    newY = math.floor((newY + half) / gridStep) * gridStep
                end

                conf2.offsetX = newX
                conf2.offsetY = newY
                MSUF_SyncUnitPositionPopup(unit, conf2)

                -- Wenn der entsprechende Tab im Optionsmenü offen ist,
                -- Slider live mitbewegen, damit nichts springt.
                if MSUF_CurrentOptionsKey == key2 then
                    local xSlider = _G["MSUF_OffsetXSlider"]
                    local ySlider = _G["MSUF_OffsetYSlider"]

                    if xSlider and xSlider.SetValue and ySlider and ySlider.SetValue then
                        -- Triggert deren OnValueChanged, welches ApplySettingsForKey(key2) aufruft.
                        xSlider:SetValue(conf2.offsetX)
                        ySlider:SetValue(conf2.offsetY)
                        -- In diesem Fall brauchen wir keine direkte Reposition,
                        -- das passiert bereits über ApplySettingsForKey.
                        return
                    end
                end

                -- Fallback: Frame direkt neu positionieren
                if key2 == "boss" then
                    -- Boss-Gruppe: immer alle 5 Frames gemeinsam bewegen
                    for i = 1, MSUF_MAX_BOSS_FRAMES do
                        local bossUnit = "boss" .. i
                        local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                        if frame then
                            PositionUnitFrame(frame, bossUnit)
                        end
                    end
                else
                    PositionUnitFrame(self, unit)
                end
            end

            if MSUF_UpdateEditModeInfo then
                MSUF_UpdateEditModeInfo()
            end
        end)
    end)

    f:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end

        if self.isDragging then
            self.isDragging = false
            self:SetScript("OnUpdate", nil)
        end
    end)
end


------------------------------------------------------
-- MSUF Edit Mode: Pfeile für Playerframe (X/Y Offsets)
------------------------------------------------------
local function MSUF_CreatePlayerEditArrows(f, unit)
    if unit ~= "player" then return end
    if f.MSUF_ArrowsCreated then return end
    f.MSUF_ArrowsCreated = true

    local function CreateArrowButton(name, parent, direction, point, relTo, relPoint, ofsX, ofsY, deltaX, deltaY)
        local btn = CreateFrame("Button", name, parent)
        btn:SetSize(18, 18)

        -- Clean dark square background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        btn._bg = bg

        -- Arrow label
        local symbols = {
            LEFT  = "<",
            RIGHT = ">",
            UP    = "^",
            DOWN  = "v",
        }
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetText(symbols[direction] or "")
        label:SetTextColor(0, 0, 0, 1)
        btn._label = label

        -- Hover / click feedback
        btn:SetScript("OnEnter", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseDown", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseUp", function(self)
            if self._bg then
                if self:IsMouseOver() then
                    self._bg:SetColorTexture(1, 1, 1, 1)
                else
                    self._bg:SetColorTexture(1, 1, 1, 1)
                end
            end
        end)

     btn:SetPoint(point, relTo or parent, relPoint or point, ofsX, ofsY)
    btn.deltaX = deltaX or 0
    btn.deltaY = deltaY or 0

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

btn:SetScript("OnClick", function(self, button)
    -- Rechtsklick: Popup für X/Y ODER Width/Height (je nach Modus)
    if button == "RightButton" then
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end

        if MSUF_OpenPositionPopup then
            MSUF_OpenPositionPopup(unit, parent)
        end
        return
    end

    -- Links-Klick: wie bisher -> nudge (verschieben / skalieren)
    if button ~= "LeftButton" then
        return
    end

    -- Nur im MSUF Edit Mode und nicht im Kampf
    if not MSUF_UnitEditModeActive then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if MSUF_NudgeUnitFrameOffset then
        MSUF_NudgeUnitFrameOffset(unit, parent, self.deltaX or 0, self.deltaY or 0)
    end
end)


        return btn
    end

    local pad = 8

    -- Links / Rechts = X-Achse
    f.MSUF_ArrowLeft  = CreateArrowButton(
        "MSUF_PlayerArrowLeft",
        f, "LEFT",
        "RIGHT", f, "LEFT",
        -pad, 0,
        -1, 0
    )

    f.MSUF_ArrowRight = CreateArrowButton(
        "MSUF_PlayerArrowRight",
        f, "RIGHT",
        "LEFT", f, "RIGHT",
        pad, 0,
        1, 0
    )

    -- Oben / Unten = Y-Achse
    f.MSUF_ArrowUp = CreateArrowButton(
        "MSUF_PlayerArrowUp",
        f, "UP",
        "BOTTOM", f, "TOP",
        0, pad,
        0, 1
    )

    f.MSUF_ArrowDown = CreateArrowButton(
        "MSUF_PlayerArrowDown",
        f, "DOWN",
        "TOP", f, "BOTTOM",
        0, -pad,
        0, -1
    )

    function f:UpdateEditArrows()
        if not (self.MSUF_ArrowLeft and self.MSUF_ArrowRight and self.MSUF_ArrowUp and self.MSUF_ArrowDown) then
            return
        end

        local show = MSUF_UnitEditModeActive and (not InCombatLockdown or not InCombatLockdown())

        if show then
            self.MSUF_ArrowLeft:Show()
            self.MSUF_ArrowRight:Show()
            self.MSUF_ArrowUp:Show()
            self.MSUF_ArrowDown:Show()
        else
            self.MSUF_ArrowLeft:Hide()
            self.MSUF_ArrowRight:Hide()
            self.MSUF_ArrowUp:Hide()
            self.MSUF_ArrowDown:Hide()
        end
    end

    -- Initialer Zustand
    f:UpdateEditArrows()
end


local function MSUF_CreateTargetEditArrows(f, unit)
    if unit ~= "target" then return end
    if f.MSUF_ArrowsCreated then return end
    f.MSUF_ArrowsCreated = true

    local function CreateArrowButton(name, parent, direction, point, relTo, relPoint, ofsX, ofsY, deltaX, deltaY)
        local btn = CreateFrame("Button", name, parent)
        btn:SetSize(18, 18)

        -- Clean dark square background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        btn._bg = bg

        -- Arrow label
        local symbols = {
            LEFT  = "<",
            RIGHT = ">",
            UP    = "^",
            DOWN  = "v",
        }
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetText(symbols[direction] or "")
        label:SetTextColor(0, 0, 0, 1)
        btn._label = label

        -- Hover / click feedback
        btn:SetScript("OnEnter", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseDown", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseUp", function(self)
            if self._bg then
                if self:IsMouseOver() then
                    self._bg:SetColorTexture(1, 1, 1, 1)
                else
                    self._bg:SetColorTexture(1, 1, 1, 1)
                end
            end
        end)

      btn:SetPoint(point, relTo or parent, relPoint or point, ofsX, ofsY)
    btn.deltaX = deltaX or 0
    btn.deltaY = deltaY or 0

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

btn:SetScript("OnClick", function(self, button)
    -- Rechtsklick: Popup für X/Y ODER Width/Height (je nach Modus)
    if button == "RightButton" then
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end

        if MSUF_OpenPositionPopup then
            MSUF_OpenPositionPopup(unit, parent)
        end
        return
    end

    -- Links-Klick: wie bisher -> nudge (verschieben / skalieren)
    if button ~= "LeftButton" then
        return
    end

    -- Nur im MSUF Edit Mode und nicht im Kampf
    if not MSUF_UnitEditModeActive then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if MSUF_NudgeUnitFrameOffset then
        MSUF_NudgeUnitFrameOffset(unit, parent, self.deltaX or 0, self.deltaY or 0)
    end
end)


        return btn
    end

    local pad = 8

    -- Links / Rechts = X-Achse
    f.MSUF_ArrowLeft  = CreateArrowButton(
        "MSUF_TargetArrowLeft",
        f, "LEFT",
        "RIGHT", f, "LEFT",
        -pad, 0,
        -1, 0
    )

    f.MSUF_ArrowRight = CreateArrowButton(
        "MSUF_TargetArrowRight",
        f, "RIGHT",
        "LEFT", f, "RIGHT",
        pad, 0,
        1, 0
    )

    -- Oben / Unten = Y-Achse
    f.MSUF_ArrowUp = CreateArrowButton(
        "MSUF_TargetArrowUp",
        f, "UP",
        "BOTTOM", f, "TOP",
        0, pad,
        0, 1
    )

    f.MSUF_ArrowDown = CreateArrowButton(
        "MSUF_TargetArrowDown",
        f, "DOWN",
        "TOP", f, "BOTTOM",
        0, -pad,
        0, -1
    )

    function f:UpdateEditArrows()
        if not (self.MSUF_ArrowLeft and self.MSUF_ArrowRight and self.MSUF_ArrowUp and self.MSUF_ArrowDown) then
            return
        end

        local show = MSUF_UnitEditModeActive and (not InCombatLockdown or not InCombatLockdown())

        if show then
            self.MSUF_ArrowLeft:Show()
            self.MSUF_ArrowRight:Show()
            self.MSUF_ArrowUp:Show()
            self.MSUF_ArrowDown:Show()
        else
            self.MSUF_ArrowLeft:Hide()
            self.MSUF_ArrowRight:Hide()
            self.MSUF_ArrowUp:Hide()
            self.MSUF_ArrowDown:Hide()
        end
    end

    -- Initialer Zustand
    f:UpdateEditArrows()
end



local function MSUF_CreateFocusEditArrows(f, unit)
    if unit ~= "focus" then return end
    if f.MSUF_ArrowsCreated then return end
    f.MSUF_ArrowsCreated = true

    local function CreateArrowButton(name, parent, direction, point, relTo, relPoint, ofsX, ofsY, deltaX, deltaY)
        local btn = CreateFrame("Button", name, parent)
        btn:SetSize(18, 18)

        -- Clean dark square background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        btn._bg = bg

        -- Arrow label
        local symbols = {
            LEFT  = "<",
            RIGHT = ">",
            UP    = "^",
            DOWN  = "v",
        }
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetText(symbols[direction] or "")
        label:SetTextColor(0, 0, 0, 1)
        btn._label = label

        -- Hover / click feedback
        btn:SetScript("OnEnter", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseDown", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseUp", function(self)
            if self._bg then
                if self:IsMouseOver() then
                    self._bg:SetColorTexture(1, 1, 1, 1)
                else
                    self._bg:SetColorTexture(1, 1, 1, 1)
                end
            end
        end)

      btn:SetPoint(point, relTo or parent, relPoint or point, ofsX, ofsY)
    btn.deltaX = deltaX or 0
    btn.deltaY = deltaY or 0

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:SetScript("OnClick", function(self, button)
    -- Rechtsklick: Popup für X/Y ODER Width/Height (je nach Modus)
    if button == "RightButton" then
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end

        if MSUF_OpenPositionPopup then
            MSUF_OpenPositionPopup(unit, parent)
        end
        return
    end

    -- Links-Klick: wie bisher -> nudge (verschieben / skalieren)
    if button ~= "LeftButton" then
        return
    end

    -- Nur im MSUF Edit Mode und nicht im Kampf
    if not MSUF_UnitEditModeActive then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if MSUF_NudgeUnitFrameOffset then
        MSUF_NudgeUnitFrameOffset(unit, parent, self.deltaX or 0, self.deltaY or 0)
    end
end)

        return btn
    end

    local pad = 8

    -- Links / Rechts = X-Achse
    f.MSUF_ArrowLeft  = CreateArrowButton(
        "MSUF_FocusArrowLeft",
        f, "LEFT",
        "RIGHT", f, "LEFT",
        -pad, 0,
        -1, 0
    )

    f.MSUF_ArrowRight = CreateArrowButton(
        "MSUF_FocusArrowRight",
        f, "RIGHT",
        "LEFT", f, "RIGHT",
        pad, 0,
        1, 0
    )

    -- Oben / Unten = Y-Achse
    f.MSUF_ArrowUp = CreateArrowButton(
        "MSUF_FocusArrowUp",
        f, "UP",
        "BOTTOM", f, "TOP",
        0, pad,
        0, 1
    )

    f.MSUF_ArrowDown = CreateArrowButton(
        "MSUF_FocusArrowDown",
        f, "DOWN",
        "TOP", f, "BOTTOM",
        0, -pad,
        0, -1
    )

    function f:UpdateEditArrows()
        if not (self.MSUF_ArrowLeft and self.MSUF_ArrowRight and self.MSUF_ArrowUp and self.MSUF_ArrowDown) then
            return
        end

        local show = MSUF_UnitEditModeActive and (not InCombatLockdown or not InCombatLockdown())

        if show then
            self.MSUF_ArrowLeft:Show()
            self.MSUF_ArrowRight:Show()
            self.MSUF_ArrowUp:Show()
            self.MSUF_ArrowDown:Show()
        else
            self.MSUF_ArrowLeft:Hide()
            self.MSUF_ArrowRight:Hide()
            self.MSUF_ArrowUp:Hide()
            self.MSUF_ArrowDown:Hide()
        end
    end

    -- Initialer Zustand
    f:UpdateEditArrows()
end



------------------------------------------------------
-- MSUF Edit Mode: Pfeile für Bossframes (X/Y Offsets)
------------------------------------------------------

------------------------------------------------------
-- MSUF Edit Mode: Pfeile für Petframe (X/Y Offsets)
------------------------------------------------------
local function MSUF_CreatePetEditArrows(f, unit)
    if unit ~= "pet" then return end
    if f.MSUF_ArrowsCreated then return end
    f.MSUF_ArrowsCreated = true

    local function CreateArrowButton(name, parent, direction, point, relTo, relPoint, ofsX, ofsY, deltaX, deltaY)
        local btn = CreateFrame("Button", name, parent)
        btn:SetSize(18, 18)

        -- Clean dark square background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        btn._bg = bg

        -- Arrow label
        local symbols = {
            LEFT  = "<",
            RIGHT = ">",
            UP    = "^",
            DOWN  = "v",
        }
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetText(symbols[direction] or "")
        label:SetTextColor(0, 0, 0, 1)
        btn._label = label

        -- Hover / click feedback
        btn:SetScript("OnEnter", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseDown", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseUp", function(self)
            if self._bg then
                if self:IsMouseOver() then
                    self._bg:SetColorTexture(1, 1, 1, 1)
                else
                    self._bg:SetColorTexture(1, 1, 1, 1)
                end
            end
        end)

      btn:SetPoint(point, relTo or parent, relPoint or point, ofsX, ofsY)
    btn.deltaX = deltaX or 0
    btn.deltaY = deltaY or 0

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

btn:SetScript("OnClick", function(self, button)
    -- Rechtsklick: Popup für X/Y ODER Width/Height (je nach Modus)
    if button == "RightButton" then
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end

        if MSUF_OpenPositionPopup then
            MSUF_OpenPositionPopup(unit, parent)
        end
        return
    end

    -- Links-Klick: wie bisher -> nudge (verschieben / skalieren)
    if button ~= "LeftButton" then
        return
    end

    -- Nur im MSUF Edit Mode und nicht im Kampf
    if not MSUF_UnitEditModeActive then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if MSUF_NudgeUnitFrameOffset then
        MSUF_NudgeUnitFrameOffset(unit, parent, self.deltaX or 0, self.deltaY or 0)
    end
end)

        return btn
    end

    local pad = 8

    -- Links / Rechts = X-Achse
    f.MSUF_ArrowLeft  = CreateArrowButton(
        "MSUF_PetArrowLeft",
        f, "LEFT",
        "RIGHT", f, "LEFT",
        -pad, 0,
        -1, 0
    )

    f.MSUF_ArrowRight = CreateArrowButton(
        "MSUF_PetArrowRight",
        f, "RIGHT",
        "LEFT", f, "RIGHT",
        pad, 0,
        1, 0
    )

    -- Oben / Unten = Y-Achse
    f.MSUF_ArrowUp = CreateArrowButton(
        "MSUF_PetArrowUp",
        f, "UP",
        "BOTTOM", f, "TOP",
        0, pad,
        0, 1
    )

    f.MSUF_ArrowDown = CreateArrowButton(
        "MSUF_PetArrowDown",
        f, "DOWN",
        "TOP", f, "BOTTOM",
        0, -pad,
        0, -1
    )

    function f:UpdateEditArrows()
        if not (self.MSUF_ArrowLeft and self.MSUF_ArrowRight and self.MSUF_ArrowUp and self.MSUF_ArrowDown) then
            return
        end

        local show = MSUF_UnitEditModeActive and (not InCombatLockdown or not InCombatLockdown())

        if show then
            self.MSUF_ArrowLeft:Show()
            self.MSUF_ArrowRight:Show()
            self.MSUF_ArrowUp:Show()
            self.MSUF_ArrowDown:Show()
        else
            self.MSUF_ArrowLeft:Hide()
            self.MSUF_ArrowRight:Hide()
            self.MSUF_ArrowUp:Hide()
            self.MSUF_ArrowDown:Hide()
        end
    end

    -- Initialer Zustand
    f:UpdateEditArrows()
end


local function MSUF_CreateBossEditArrows(f, unit)
    if type(unit) ~= "string" or not unit:match("^boss%d+$") then return end
    if f.MSUF_ArrowsCreated then return end
    f.MSUF_ArrowsCreated = true

    local function CreateArrowButton(name, parent, direction, point, relTo, relPoint, ofsX, ofsY, deltaX, deltaY)
        local btn = CreateFrame("Button", name, parent)
        btn:SetSize(18, 18)

        -- Clean dark square background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        btn._bg = bg

        -- Arrow label
        local symbols = {
            LEFT  = "<",
            RIGHT = ">",
            UP    = "^",
            DOWN  = "v",
        }
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetText(symbols[direction] or "")
        label:SetTextColor(0, 0, 0, 1)
        btn._label = label

        -- Hover / click feedback
        btn:SetScript("OnEnter", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseDown", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseUp", function(self)
            if self._bg then
                if self:IsMouseOver() then
                    self._bg:SetColorTexture(1, 1, 1, 1)
                else
                    self._bg:SetColorTexture(1, 1, 1, 1)
                end
            end
        end)
    btn:SetPoint(point, relTo or parent, relPoint or point, ofsX, ofsY)
    btn.deltaX = deltaX or 0
    btn.deltaY = deltaY or 0

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:SetScript("OnClick", function(self, button)
    -- Rechtsklick: Popup für X/Y ODER Width/Height (je nach Modus)
    if button == "RightButton" then
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end

        if MSUF_OpenPositionPopup then
            MSUF_OpenPositionPopup(unit, parent)
        end
        return
    end

    -- Links-Klick: wie bisher -> nudge (verschieben / skalieren)
    if button ~= "LeftButton" then
        return
    end

    -- Nur im MSUF Edit Mode und nicht im Kampf
    if not MSUF_UnitEditModeActive then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if MSUF_NudgeUnitFrameOffset then
        MSUF_NudgeUnitFrameOffset(unit, parent, self.deltaX or 0, self.deltaY or 0)
    end
end)

        return btn
    end

    local pad = 8
    local prefix = "MSUF_" .. unit  -- z.B. "MSUF_boss1"

    -- Links / Rechts = X-Achse
    f.MSUF_ArrowLeft  = CreateArrowButton(
        prefix .. "_ArrowLeft",
        f, "LEFT",
        "RIGHT", f, "LEFT",
        -pad, 0,
        -1, 0
    )

    f.MSUF_ArrowRight = CreateArrowButton(
        prefix .. "_ArrowRight",
        f, "RIGHT",
        "LEFT", f, "RIGHT",
        pad, 0,
        1, 0
    )

    -- Oben / Unten = Y-Achse
    f.MSUF_ArrowUp = CreateArrowButton(
        prefix .. "_ArrowUp",
        f, "UP",
        "BOTTOM", f, "TOP",
        0, pad,
        0, 1
    )

    f.MSUF_ArrowDown = CreateArrowButton(
        prefix .. "_ArrowDown",
        f, "DOWN",
        "TOP", f, "BOTTOM",
        0, -pad,
        0, -1
    )

    function f:UpdateEditArrows()
        if not (self.MSUF_ArrowLeft and self.MSUF_ArrowRight and self.MSUF_ArrowUp and self.MSUF_ArrowDown) then
            return
        end

        local show = MSUF_UnitEditModeActive and (not InCombatLockdown or not InCombatLockdown())

        if show then
            self.MSUF_ArrowLeft:Show()
            self.MSUF_ArrowRight:Show()
            self.MSUF_ArrowUp:Show()
            self.MSUF_ArrowDown:Show()
        else
            self.MSUF_ArrowLeft:Hide()
            self.MSUF_ArrowRight:Hide()
            self.MSUF_ArrowUp:Hide()
            self.MSUF_ArrowDown:Hide()
        end
    end

    -- Initialer Zustand
    f:UpdateEditArrows()
end


local function MSUF_CreateTargetTargetEditArrows(f, unit)
    if unit ~= "targettarget" then return end
    if f.MSUF_ArrowsCreated then return end
    f.MSUF_ArrowsCreated = true

    local function CreateArrowButton(name, parent, direction, point, relTo, relPoint, ofsX, ofsY, deltaX, deltaY)
        local btn = CreateFrame("Button", name, parent)
        btn:SetSize(18, 18)

        -- Clean dark square background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        btn._bg = bg

        -- Arrow label
        local symbols = {
            LEFT  = "<",
            RIGHT = ">",
            UP    = "^",
            DOWN  = "v",
        }
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetText(symbols[direction] or "")
        label:SetTextColor(0, 0, 0, 1)
        btn._label = label

        -- Hover / click feedback
        btn:SetScript("OnEnter", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseDown", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnMouseUp", function(self)
            if self._bg then
                if self:IsMouseOver() then
                    self._bg:SetColorTexture(1, 1, 1, 1)
                else
                    self._bg:SetColorTexture(1, 1, 1, 1)
                end
            end
        end)

       btn:SetPoint(point, relTo or parent, relPoint or point, ofsX, ofsY)
    btn.deltaX = deltaX or 0
    btn.deltaY = deltaY or 0

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

btn:SetScript("OnClick", function(self, button)
    -- Rechtsklick: Popup für X/Y ODER Width/Height (je nach Modus)
    if button == "RightButton" then
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end

        if MSUF_OpenPositionPopup then
            MSUF_OpenPositionPopup(unit, parent)
        end
        return
    end

    -- Links-Klick: wie bisher -> nudge (verschieben / skalieren)
    if button ~= "LeftButton" then
        return
    end

    -- Nur im MSUF Edit Mode und nicht im Kampf
    if not MSUF_UnitEditModeActive then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if MSUF_NudgeUnitFrameOffset then
        MSUF_NudgeUnitFrameOffset(unit, parent, self.deltaX or 0, self.deltaY or 0)
    end
end)

        return btn
    end

    local pad = 8

    -- Links / Rechts = X-Achse
    f.MSUF_ArrowLeft  = CreateArrowButton(
        "MSUF_TargetTargetArrowLeft",
        f, "LEFT",
        "RIGHT", f, "LEFT",
        -pad, 0,
        -1, 0
    )

    f.MSUF_ArrowRight = CreateArrowButton(
        "MSUF_TargetTargetArrowRight",
        f, "RIGHT",
        "LEFT", f, "RIGHT",
        pad, 0,
        1, 0
    )

    -- Oben / Unten = Y-Achse
    f.MSUF_ArrowUp = CreateArrowButton(
        "MSUF_TargetTargetArrowUp",
        f, "UP",
        "BOTTOM", f, "TOP",
        0, pad,
        0, 1
    )

    f.MSUF_ArrowDown = CreateArrowButton(
        "MSUF_TargetTargetArrowDown",
        f, "DOWN",
        "TOP", f, "BOTTOM",
        0, -pad,
        0, -1
    )

    function f:UpdateEditArrows()
        if not (self.MSUF_ArrowLeft and self.MSUF_ArrowRight and self.MSUF_ArrowUp and self.MSUF_ArrowDown) then
            return
        end

        local show = MSUF_UnitEditModeActive and (not InCombatLockdown or not InCombatLockdown())

        if show then
            self.MSUF_ArrowLeft:Show()
            self.MSUF_ArrowRight:Show()
            self.MSUF_ArrowUp:Show()
            self.MSUF_ArrowDown:Show()
        else
            self.MSUF_ArrowLeft:Hide()
            self.MSUF_ArrowRight:Hide()
            self.MSUF_ArrowUp:Hide()
            self.MSUF_ArrowDown:Hide()
        end
    end

    -- Initialer Zustand
    f:UpdateEditArrows()
end


local function CreateSimpleUnitFrame(unit)
    EnsureDB()

    local key  = GetConfigKeyForUnit(unit)
    local conf = key and MSUF_DB[key] or {}

    local f = CreateFrame("Button", "MSUF_" .. unit, UIParent, "SecureUnitButtonTemplate")
    f.unit = unit
 -- verhindert, dass Frames komplett vom Bildschirm verschwinden
    f:SetClampedToScreen(true)
    if unit == "player" or unit == "target" then
        local w = conf.width  or 275
        local h = conf.height or 40
        f:SetSize(w, h)
        f.showName      = conf.showName  ~= false
        f.showHPText    = conf.showHP    ~= false
        f.showPowerText = conf.showPower ~= false
        f.isBoss        = false

    elseif unit == "focus" then
        local w = conf.width  or 220
        local h = conf.height or 30
        f:SetSize(w, h)
        f.showName      = conf.showName  ~= false
        f.showHPText    = conf.showHP    or false
        f.showPowerText = conf.showPower or false
        f.isBoss        = false

    elseif unit == "targettarget" then
        local w = conf.width  or 220
        local h = conf.height or 30
        f:SetSize(w, h)
        f.showName      = conf.showName  ~= false
        f.showHPText    = conf.showHP    ~= false
        f.showPowerText = conf.showPower or false
        f.isBoss        = false

    elseif unit == "pet" then
        local w = conf.width  or 220
        local h = conf.height or 30
        f:SetSize(w, h)
        f.showName      = conf.showName  ~= false
        f.showHPText    = conf.showHP    ~= false
        f.showPowerText = conf.showPower ~= false
        f.isBoss        = false

    elseif unit:match("^boss%d+$") then
        local w = conf.width  or 220
        local h = conf.height or 30
        f:SetSize(w, h)
        f.showName      = conf.showName  ~= false
        f.showHPText    = conf.showHP    ~= false
        f.showPowerText = conf.showPower ~= false
        f.isBoss        = true
        f:Hide()
    end

    PositionUnitFrame(f, unit)

    --------------------------------------------------
    --------------------------------------------------
    -- MSUF Edit Mode: Drag-Logik für alle Unitframes
    --------------------------------------------------
    if unit == "player"
        or unit == "target"
        or unit == "focus"
        or unit == "targettarget"
        or unit == "pet"
        or (type(unit) == "string" and unit:match("^boss%d+$"))
    then
        MSUF_EnableUnitFrameDrag(f, unit)
    end

    --------------------------------------------------
    -- MSUF Edit Mode: Pfeile für Player, Target, Focus, Pet, Boss & Target-of-Target
    --------------------------------------------------
    if unit == "player" then
        MSUF_CreatePlayerEditArrows(f, unit)
    elseif unit == "target" then
        MSUF_CreateTargetEditArrows(f, unit)
    elseif unit == "focus" then
        MSUF_CreateFocusEditArrows(f, unit)
    elseif unit == "pet" then
        MSUF_CreatePetEditArrows(f, unit)
    elseif unit == "targettarget" then
        MSUF_CreateTargetTargetEditArrows(f, unit)
    elseif type(unit) == "string" and unit:match("^boss%d+$") then
        MSUF_CreateBossEditArrows(f, unit)
    end

    f:RegisterForClicks("AnyUp")
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    -- Register this frame for mouseover / click-casting addons (Clique, etc.)
    if ClickCastFrames then
        ClickCastFrames[f] = true
    end

    local bg = f:CreateTexture(nil, "BACKGROUND")
    -- Statt über den ganzen Frame: exakt auf die Größe der HP-Bar ziehen
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    f.bg = bg

    local hpBar = CreateFrame("StatusBar", nil, f)
    hpBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    hpBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    hpBar:SetStatusBarTexture(MSUF_GetBarTexture())
    hpBar:SetMinMaxValues(0, 1)
    hpBar:SetValue(0)
    hpBar:SetFrameLevel(f:GetFrameLevel() + 1)
    f.hpBar = hpBar

    -- Gradient-Overlay für HP-Bar (kompatibel mit allen Clients)
    local hpGradient = hpBar:CreateTexture(nil, "OVERLAY")
    hpGradient:SetAllPoints(hpBar)
    hpGradient:SetTexture("Interface\\Buttons\\WHITE8x8")

    -- Wende die konfigurierbare Gradient-Logik an
    MSUF_ApplyHPGradient(hpGradient)

    hpGradient:SetBlendMode("BLEND")
    f.hpGradient = hpGradient
        -- Simple damage-absorb overlay (PW:Shield etc.) – hellblau, von rechts nach links
    local absorbBar = CreateFrame("StatusBar", nil, f)
    absorbBar:SetAllPoints(hpBar)
    absorbBar:SetStatusBarTexture(MSUF_GetBarTexture())
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)
    absorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 2)
    absorbBar:SetStatusBarColor(0.8, 0.9, 1.0, 0.6)
    if absorbBar.SetReverseFill then
        absorbBar:SetReverseFill(true)
    end
    absorbBar:Hide()
    f.absorbBar = absorbBar

    -- Simple heal-absorb overlay (Heilung blockiert) – rötlich, normal von links nach rechts
    local healAbsorbBar = CreateFrame("StatusBar", nil, f)
    healAbsorbBar:SetAllPoints(hpBar)
    healAbsorbBar:SetStatusBarTexture(MSUF_GetBarTexture())
    healAbsorbBar:SetMinMaxValues(0, 1)
    healAbsorbBar:SetValue(0)
    healAbsorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 3)
    healAbsorbBar:SetStatusBarColor(1.0, 0.4, 0.4, 0.7)
    if healAbsorbBar.SetReverseFill then
        healAbsorbBar:SetReverseFill(false)
    end
    healAbsorbBar:Hide()
    f.healAbsorbBar = healAbsorbBar

    -- Simple absorb overlay bar oben auf der HP-Bar
    local absorbBar = CreateFrame("StatusBar", nil, f)
    absorbBar:SetAllPoints(hpBar)
    absorbBar:SetStatusBarTexture(MSUF_GetBarTexture())
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)

    -- Über der normalen HP-Bar + Gradient
    absorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 2)

    -- Leicht blaues Overlay
    absorbBar:SetStatusBarColor(0.8, 0.9, 1.0, 0.6)

    -- Wenn verfügbar, von rechts nach links füllen lassen (klassischer Absorb-Look)
    if absorbBar.SetReverseFill then
        absorbBar:SetReverseFill(true)
    end

    absorbBar:Hide()
    f.absorbBar = absorbBar
    -- small power bar under player / focus / target / boss frames
    if unit == "player" or unit == "focus" or unit == "target" or unit:match("^boss%d+$") then
        local pBar = CreateFrame("StatusBar", nil, f)
        pBar:SetStatusBarTexture(MSUF_GetBarTexture())

        local height = 3
        if MSUF_DB and MSUF_DB.bars and type(MSUF_DB.bars.powerBarHeight) == "number" and MSUF_DB.bars.powerBarHeight > 0 then
            height = MSUF_DB.bars.powerBarHeight
        end
        pBar:SetHeight(height)

        -- an die HP-Bar / Hintergrund anschließen statt an den Frame
        -- 0, -1 = 1 Pixel Abstand; bei 0, 0 klebt sie direkt dran
        pBar:SetPoint("TOPLEFT",  hpBar, "BOTTOMLEFT",  0, -1)
        pBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, -1)
        pBar:SetMinMaxValues(0, 1)
        pBar:SetValue(0)
        pBar:SetFrameLevel(hpBar:GetFrameLevel())
        f.targetPowerBar = pBar
        pBar:Hide()
    end


    local textFrame = CreateFrame("Frame", nil, f)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    f.textFrame = textFrame

    local fontPath = MSUF_GetFontPath()
    local flags    = MSUF_GetFontFlags()

    local nameText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetFont(fontPath, 14, flags)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(1, 1, 1, 1)
    f.nameText = nameText

    local hpText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hpText:SetFont(fontPath, 14, flags)
    hpText:SetJustifyH("RIGHT")
    hpText:SetTextColor(1, 1, 1, 0.9)
    f.hpText = hpText

    local powerText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerText:SetFont(fontPath, 14, flags)
    powerText:SetJustifyH("RIGHT")
    powerText:SetTextColor(1, 1, 1, 0.9)
    f.powerText = powerText

    ApplyTextLayout(f, conf)

    -- Leader icon (group leader indicator) for player and target
    if unit == "player" or unit == "target" then
        local leaderIcon = f:CreateTexture(nil, "OVERLAY")
        leaderIcon:SetSize(16, 16)
        leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        if unit == "player" then
            leaderIcon:SetPoint("LEFT", f, "TOPLEFT", 0, 3)
        else
            leaderIcon:SetPoint("LEFT", f, "TOPLEFT", 0, 3)
        end
        leaderIcon:Hide()
        f.leaderIcon = leaderIcon
    end


    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("UNIT_NAME_UPDATE")
    f:RegisterEvent("UNIT_POWER_UPDATE")
    f:RegisterEvent("UNIT_MAXPOWER")
    f:RegisterEvent("UNIT_HEALTH")
    f:RegisterEvent("UNIT_MAXHEALTH")
    f:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    f:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_FOCUS_CHANGED")
    f:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")

    -- Group leader changes (for player/target frames)
    if unit == "player" or unit == "target" then
        f:RegisterEvent("GROUP_ROSTER_UPDATE")
        f:RegisterEvent("PARTY_LEADER_CHANGED")
    end

    if unit == "target" then
        f:RegisterEvent("UNIT_AURA")
    end

    -- Target-of-Target needs UNIT_TARGET to update when your or your target's target changes
    if unit == "targettarget" then
        f:RegisterEvent("UNIT_TARGET")
    end

    f:SetScript("OnEvent", function(self, event, arg1)
        -- 1) Aura-Events: nur fürs Target interessant
        if event == "UNIT_AURA" then
            if self.unit == "target" and arg1 == "target" then
                MSUF_UpdateTargetAuras(self)
            end
            return
        end

              -- 2) Unit-spezifische Events: nur updaten, wenn das Event wirklich unser Unit betrifft
        if event == "UNIT_HEALTH"
            or event == "UNIT_MAXHEALTH"
            or event == "UNIT_POWER_UPDATE"
            or event == "UNIT_MAXPOWER"
            or event == "UNIT_NAME_UPDATE"
            or event == "UNIT_ABSORB_AMOUNT_CHANGED"
            or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
        then
            -- Für die meisten Frames filtern wir nach arg1, um Spam zu vermeiden.
            -- Target-of-Target ist aber speziell: dort wollen wir IMMER updaten,
            -- weil 12.0 teilweise "geheime" Unit-Tokens an UNIT_* Events hängt.
            if self.unit ~= "targettarget" and arg1 ~= self.unit then
                return
            end


        elseif event == "PLAYER_TARGET_CHANGED" then
            -- Target-of-Target also needs to update when your target changes
            if self.unit ~= "target" and self.unit ~= "targettarget" then
                return
            end
        elseif event == "PLAYER_FOCUS_CHANGED" then
            if self.unit ~= "focus" then
                return
            end
        elseif event == "UNIT_TARGET" then
            -- Only the ToT frame cares about UNIT_TARGET; other frames can ignore it
            if self.unit ~= "targettarget" then
                return
            end
        end

        -- 3) Frame-Update nur, wenn wir das Event wirklich brauchen (mit globalem Throttle)
        local interval = MSUF_FrameUpdateInterval
        if type(interval) ~= "number" or interval <= 0 then
            interval = 0.05
        end

        local doUpdate = true
        if interval and interval > 0 then
            local now = GetTime and GetTime() or 0
            local last = self._msufLastUpdate or 0
            if (now - last) < interval then
                doUpdate = false
            else
                self._msufLastUpdate = now
            end
        end

        if doUpdate then
            UpdateSimpleUnitFrame(self)
        end

        -- 4) Target-Auren: nur bei Events, wo sich Auren plausibel ändern
        if self.unit == "target" then
            if event == "PLAYER_TARGET_CHANGED"
                or event == "PLAYER_ENTERING_WORLD"
                or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT"
            then
                MSUF_UpdateTargetAuras(self)
            end
        end
    end)


    --------------------------------------------------
    -- Mouseover highlight border
    --------------------------------------------------
    f:EnableMouse(true)

    local highlight = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate")
    f.highlightBorder = highlight

    highlight:SetPoint("TOPLEFT", f.hpBar, "TOPLEFT", -3, 3)
    highlight:SetPoint("BOTTOMRIGHT", f.hpBar, "BOTTOMRIGHT", 3, -3)
    highlight:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    highlight:Hide()

    function f:UpdateHighlightColor()
        EnsureDB()
        local g = MSUF_DB.general or {}
        local key   = (g.highlightColor or "white"):lower()
        local color = MSUF_FONT_COLORS[key] or MSUF_FONT_COLORS.white
        local r, gCol, b = color[1], color[2], color[3]
        self.highlightBorder:SetBackdropBorderColor(r, gCol, b, 1)
    end

    f:SetScript("OnEnter", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}

        -- Highlight wie bisher
        if g.highlightEnabled == false then
            if self.highlightBorder then
                self.highlightBorder:Hide()
            end
        else
            if self.highlightBorder then
                self:UpdateHighlightColor()
                self.highlightBorder:Show()
            end
        end

        -- Wenn deaktiviert, keinerlei Info-Panel anzeigen
        if g.disableUnitInfoTooltips then
            return
        end

        -- Eigene Info-Anzeige: Spieler, Target, Focus, Target-of-Target, Pet und Boss
        -- bekommen ein Info-Panel, komplett getrennt vom GameTooltip.
        if self.unit == "player" and UnitExists("player") then
            MSUF_ShowPlayerInfoTooltip()
        elseif self.unit == "target" and UnitExists("target") then
            MSUF_ShowTargetInfoTooltip()
        elseif self.unit == "focus" and UnitExists("focus") then
            MSUF_ShowFocusInfoTooltip()
        elseif self.unit == "targettarget" and UnitExists("targettarget") then
            MSUF_ShowTargetTargetInfoTooltip()
        elseif self.unit == "pet" and UnitExists("pet") then
            MSUF_ShowPetInfoTooltip()
        elseif self.unit and string.sub(self.unit, 1, 4) == "boss" and UnitExists(self.unit) then
            MSUF_ShowBossInfoTooltip(self.unit)
        end
    end)



f:SetScript("OnLeave", function(self)
        if self.highlightBorder then
            self.highlightBorder:Hide()
        end

        if self.unit == "player" or self.unit == "target" or self.unit == "focus" or self.unit == "targettarget" or self.unit == "pet" or (self.unit and string.sub(self.unit, 1, 4) == "boss") then
            MSUF_HidePlayerInfoTooltip()
        end

        GameTooltip:Hide()
    end)





    UpdateSimpleUnitFrame(f)
    if unit == "target" then
        MSUF_UpdateTargetAuras(f)
    end
    UnitFrames[unit] = f
end
local function MSUF_CreateCheck(parent, text, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb.text = cb:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.text:SetText(text)
    return cb
end


------------------------------------------------------
-- OPTIONS PANEL
------------------------------------------------------
local function CreateOptionsPanel()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end

    EnsureDB()

    

------------------------------------------------------
-- Power bar height helper
------------------------------------------------------
local function MSUF_UpdatePowerBarHeightFromEdit(editBox)
    if not editBox or not editBox.GetText then return end

    text = editBox:GetText()
    v = tonumber(text or "")
    if not v or v <= 0 then
        v = 3
    end
    if v > 50 then
        v = 50
    end

    editBox:SetText(tostring(v))

    EnsureDB()
    MSUF_DB.bars = MSUF_DB.bars or {}
    MSUF_DB.bars.powerBarHeight = v

    -- Apply immediately to all relevant frames (no OnUpdate spam)
    if UnitFrames then
        units = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
        for _, key in ipairs(units) do
            f = UnitFrames[key]
            if f and f.targetPowerBar then
                f.targetPowerBar:SetHeight(v)
            end
        end
    end

    ApplyAllSettings()
end


panel = CreateFrame("Frame")
    panel.name = "Midnight Simple Unit Frames"

    title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("Midnight Simple Unit Frames (Beta)")

    sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetText("Thank you for using MSUP. Please give feedback in the Discord. v1.0 Beta")

    --------------------------------------------------
    -- GROUP FRAMES: frame settings vs font settings
    --------------------------------------------------
    frameGroup = CreateFrame("Frame", nil, panel)
    frameGroup:SetAllPoints()

    fontGroup = CreateFrame("Frame", nil, panel)
    fontGroup:SetAllPoints()

    -- Neues Group-Frame für Auren / Bufftracking
    auraGroup = CreateFrame("Frame", nil, panel)
    auraGroup:SetAllPoints()

    -- Neues Group-Frame für Castbar-Einstellungen (mit Sub-Panels)
    castbarGroup = CreateFrame("Frame", nil, panel)
    castbarGroup:SetAllPoints()

    -- Sub-Panels innerhalb des Castbar-Tabs:
    -- 1) castbarEnemyGroup = Target/Focus/Pet (bestehende Optionen)
    -- 2) castbarPlayerGroup = Player-Castbar (noch leer, Vorbereitung)
    castbarEnemyGroup = CreateFrame("Frame", "MSUF_CastbarEnemyGroup", castbarGroup)
    castbarEnemyGroup:SetAllPoints()

    castbarTargetGroup = CreateFrame("Frame", "MSUF_CastbarTargetGroup", castbarGroup)
    castbarTargetGroup:SetAllPoints()
    castbarTargetGroup:Hide()

    castbarFocusGroup = CreateFrame("Frame", "MSUF_CastbarFocusGroup", castbarGroup)
    castbarFocusGroup:SetAllPoints()
    castbarFocusGroup:Hide()

    castbarPlayerGroup = CreateFrame("Frame", "MSUF_CastbarPlayerGroup", castbarGroup)
    castbarPlayerGroup:SetAllPoints()
    castbarPlayerGroup:Hide()

    -- Neues Group-Frame für Balken / HP-Bar-Optik
    barGroup = CreateFrame("Frame", nil, panel)
    barGroup:SetAllPoints()

    -- Neues Group-Frame für Misc / Mouseover-Highlight
    miscGroup = CreateFrame("Frame", nil, panel)
    miscGroup:SetAllPoints()

    -- Neues Group-Frame für Profile / Import / Export
    profileGroup = CreateFrame("Frame", nil, panel)
    profileGroup:SetAllPoints()

    --------------------------------------------------
    -- FRAME TYPE BUTTONS (incl. Fonts-Tab)
    --------------------------------------------------
    currentKey = "player"
    buttons = {}
    local editModeButton


    local function GetLabelForKey(key)
        if key == "player" then
            return "Player"
        elseif key == "target" then
            return "Target"
        elseif key == "targettarget" then
            return "Target of Target"
         elseif key == "focus" then
            return "Focus"
        elseif key == "pet" then
            return "Pet"
        elseif key == "boss" then
            return "Boss Frames"
        elseif key == "bars" then
            return "Bars"
        elseif key == "fonts" then
            return "Fonts"
        elseif key == "auras" then
            return "Auras"
        elseif key == "castbar" then
            return "Castbar"
        elseif key == "misc" then
            return "Miscellaneous"
        elseif key == "profiles" then
            return "Profiles"
        end
        return key
    end

    local function UpdateGroupVisibility()
        if currentKey == "fonts" then
            frameGroup:Hide()
            fontGroup:Show()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentKey == "bars" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Show()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentKey == "auras" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Show()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentKey == "castbar" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Show()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentKey == "misc" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Show()
            profileGroup:Hide()
        elseif currentKey == "profiles" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Show()
        else
            frameGroup:Show()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()
        end

        -- Edit Mode button visibility (only for unit-specific tabs)
        if editModeButton then
            if currentKey == "player"
                or currentKey == "target"
                or currentKey == "targettarget"
                or currentKey == "focus"
                or currentKey == "boss"
            then
                editModeButton:Show()
            else
                editModeButton:Hide()
            end
        end
    end

    local function SetCurrentKey(newKey)
        currentKey = newKey
        MSUF_CurrentOptionsKey = newKey
        for k, b in pairs(buttons) do
            b:Enable()
        end
        if buttons[newKey] then
            buttons[newKey]:Disable()
        end
        UpdateGroupVisibility()
    end

    local function CreateUnitButton(key, xOffset, yOffset)
        b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(90, 22)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + (xOffset or 0), yOffset or -50)
        b:SetText(GetLabelForKey(key))
        b:SetScript("OnClick", function()
            SetCurrentKey(key)
            panel:LoadFromDB()
        end)
        buttons[key] = b
    end

    -- first row: unit frames
    CreateUnitButton("player",        0,   -50)
    CreateUnitButton("target",      100,   -50)
    CreateUnitButton("targettarget",200,   -50)
    CreateUnitButton("focus",       300,   -50)
    CreateUnitButton("boss",        400,   -50)
    CreateUnitButton("pet",         500,   -50)

    -- second row: global tabs
    CreateUnitButton("bars",          0,   -80)
    CreateUnitButton("fonts",       100,   -80)
    CreateUnitButton("auras",       200,   -80)
    CreateUnitButton("castbar",     300,   -80)
    CreateUnitButton("misc",        400,   -80)
    CreateUnitButton("profiles",    500,   -80)

    -- Big "Edit Mode" button at the bottom left
    editModeButton = CreateFrame("Button", "MSUF_EditModeButton", panel, "UIPanelButtonTemplate")
    editModeButton:SetSize(160, 32)  -- fairly large
    editModeButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 16)
    editModeButton:SetText("Edit Mode")

    -- Hint text: explain that global X/Y is handled via Edit Mode + arrows
    editHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    editHint:SetPoint("LEFT", editModeButton, "RIGHT", 12, 0)
    editHint:SetJustifyH("LEFT")
    editHint:SetText("") -- text removed for cleaner bottom area
        -- Snap-to-Grid Toggle für Edit Mode
    snapCheck = CreateFrame("CheckButton", "MSUF_EditModeSnapCheck", panel, "UICheckButtonTemplate")
    snapCheck:SetPoint("LEFT", editHint, "RIGHT", 16, 0)

    snapText = _G["MSUF_EditModeSnapCheckText"]
    if snapText then
        snapText:SetText("Snap to grid")
    end
    snapCheck.text = snapText

    EnsureDB()
    g = MSUF_DB.general or {}
    snapCheck:SetChecked(g.editModeSnapToGrid ~= false)

    snapCheck:SetScript("OnClick", function(self)
        EnsureDB()
        gg = MSUF_DB.general
        gg.editModeSnapToGrid = self:GetChecked() and true or false
    end)
    -- ⬇ add this line, so the option in the panel is hidden
    snapCheck:Hide()

  -- Larger font for visibility
emFont = editModeButton:GetFontString()
if emFont then
    emFont:SetFontObject("GameFontNormalLarge")
end
-- Simple sync: Castbar-Preview folgt dem großen MSUF Edit Mode
    function MSUF_SyncCastbarEditModeWithUnitEdit()
    if not MSUF_DB or not MSUF_DB.general then
        return
    end

    g = MSUF_DB.general

    -- Wenn der große Edit Mode an ist -> Castbar-Preview an,
    -- wenn er aus ist -> Castbar-Preview aus.
    g.castbarPlayerPreviewEnabled = MSUF_UnitEditModeActive and true or false

    -- Previews aktualisieren (Player/Target/Focus)
    if MSUF_UpdatePlayerCastbarPreview then
        MSUF_UpdatePlayerCastbarPreview()
    end
end
-- Click: toggle internal MSUF edit mode
editModeButton:SetScript("OnClick", function()
    -- Edit Mode nur für Unit-Tabs erlauben
    movableKeys = {
        player       = true,
        target       = true,
        targettarget = true,
        focus        = true,
        pet          = true,
        boss         = true,
    }

    if not movableKeys[currentKey] then
        print("|cffffd700MSUF:|r Edit Mode only works for unit tabs (Player/Target/ToT/Focus/Pet/Boss). Please select one of those tabs.")
        return
    end

    -- Zustand togglen
    MSUF_UnitEditModeActive = not MSUF_UnitEditModeActive
    MSUF_CurrentEditUnitKey = MSUF_UnitEditModeActive and currentKey or nil
    label = GetLabelForKey(currentKey) or currentKey
    
    -- NEU: Castbar-Edit-Mode an den großen Edit-Mode koppeln
    MSUF_SyncCastbarEditModeWithUnitEdit()
    if MSUF_UnitEditModeActive then
        -- ✅ Offene Blizzard-Options sauber schließen, damit ESC danach wieder normal funktioniert
        if SettingsPanel and SettingsPanel:IsShown() then
            if HideUIPanel then
                HideUIPanel(SettingsPanel)
            else
                SettingsPanel:Hide()
            end
        elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            if HideUIPanel then
                HideUIPanel(InterfaceOptionsFrame)
            else
                InterfaceOptionsFrame:Hide()
            end
        elseif VideoOptionsFrame and VideoOptionsFrame:IsShown() then
            if HideUIPanel then
                HideUIPanel(VideoOptionsFrame)
            else
                VideoOptionsFrame:Hide()
            end
        elseif AudioOptionsFrame and AudioOptionsFrame:IsShown() then
            if HideUIPanel then
                HideUIPanel(AudioOptionsFrame)
            else
                AudioOptionsFrame:Hide()
            end
        end

  --------------------------------------------------
                        print("|cffffd700MSUF:|r " .. label .. " Edit Mode |cff00ff00ON|r – drag the " .. label .. " frame with the left mouse button or use the arrow buttons.")
        else
            -- (Boss-Preview lassen wir an – kannst du weiter über die Checkbox steuern)
            print("|cffffd700MSUF:|r " .. label .. " Edit Mode |cffff0000OFF|r.")
        end

    -- Edit-Visuals (Pfeile, Grid etc.) aktualisieren
   if MSUF_UpdateEditModeVisuals then
            MSUF_UpdateEditModeVisuals()
    end
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
        end
    end)

--------------------------------------------------
    -- 
    --------------------------------------------------
    -- HELPERS: SLIDER + EDITBOX + +/- Buttons
    --------------------------------------------------

    ------------------------------------------------------
    -- GLOBAL SLIDER STYLE (flat + hover highlight)
    ------------------------------------------------------
    local function MSUF_StyleSlider(slider)
        if not slider or slider.MSUFStyled then return end
        slider.MSUFStyled = true

        -- Slightly flatter slider
        slider:SetHeight(14)

        -- Dark track behind the thumb
        track = slider:CreateTexture(nil, "BACKGROUND")
        slider.MSUFTrack = track
        track:SetColorTexture(0.06, 0.06, 0.06, 1)
        track:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, -3)
        track:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 0, 3)

        -- Smaller thumb
        thumb = slider:GetThumbTexture()
        if thumb then
            thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            thumb:SetSize(10, 18)
        end

        -- Hover: slightly brighten the track
        slider:HookScript("OnEnter", function(self)
            if self.MSUFTrack then
                self.MSUFTrack:SetColorTexture(0.20, 0.20, 0.20, 1)
            end
        end)

        slider:HookScript("OnLeave", function(self)
            if self.MSUFTrack then
                self.MSUFTrack:SetColorTexture(0.06, 0.06, 0.06, 1)
            end
        end)
    end

    ------------------------------------------------------
    -- SMALL +/- BUTTON STYLE
    ------------------------------------------------------
local function MSUF_StyleSmallButton(button, isPlus)
    if not button or button.MSUFStyled then return end
    button.MSUFStyled = true

    -- Größe
    button:SetSize(20, 20)

    -- Flacher Midnight-Hintergrund (über WHITE8x8)
    normal = button:CreateTexture(nil, "BACKGROUND")
    normal:SetAllPoints()
    normal:SetTexture(MSUF_TEX_WHITE8)
    normal:SetVertexColor(0, 0, 0, 0.9) -- fast schwarz
    button:SetNormalTexture(normal)

    pushed = button:CreateTexture(nil, "BACKGROUND")
    pushed:SetAllPoints()
    pushed:SetTexture(MSUF_TEX_WHITE8)
    pushed:SetVertexColor(0.7, 0.55, 0.15, 0.95) -- dunkles Gold beim Klick
    button:SetPushedTexture(pushed)

    highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(MSUF_TEX_WHITE8)
    highlight:SetVertexColor(1, 0.9, 0.4, 0.25) -- goldener Hover
    button:SetHighlightTexture(highlight)

    -- Dünner Rahmen
    border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    border:SetAllPoints()
border:SetBackdrop({
    edgeFile = MSUF_TEX_WHITE8,
    edgeSize = 1,
})
    border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Text (+ / -)
    fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    fs:SetTextColor(1, 0.9, 0.4) -- Gold
    fs:SetText(isPlus and "+" or "-")
    button.text = fs
end
local function CreateLabeledSlider(name, label, parent, minVal, maxVal, step, x, y)
    -- Create the slider
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")

    -- Vertical offset so content sits below the two button rows
    local extraY = 0
    if parent == frameGroup or parent == fontGroup or parent == barGroup or parent == profileGroup then
        extraY = -40
    end

    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y + extraY)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    slider.minVal = minVal
    slider.maxVal = maxVal
    slider.step   = step

    -- Standard texts from the template
    local low  = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local text = _G[name .. "Text"]

    if low  then low:SetText(tostring(minVal)) end
    if high then high:SetText(tostring(maxVal)) end
    if text then text:SetText(label or "")     end

    -- Input box below the slider
    local eb = CreateFrame("EditBox", name .. "Input", parent, "InputBoxTemplate")
    eb:SetSize(60, 18)
    eb:SetAutoFocus(false)
    eb:SetPoint("TOP", slider, "BOTTOM", 0, -8) -- more spacing
    eb:SetJustifyH("CENTER")
    slider.editBox = eb

    local function ApplyEditBoxValue()
        local txt = eb:GetText()
        local val = tonumber(txt)
        if not val then
            -- Invalid input -> revert to current slider value
            local cur = slider:GetValue() or minVal
            if slider.step and slider.step >= 1 then
                cur = math.floor(cur + 0.5)
            end
            eb:SetText(tostring(cur))
            return
        end

        if val < slider.minVal then val = slider.minVal end
        if val > slider.maxVal then val = slider.maxVal end
        slider:SetValue(val)
    end

    eb:SetScript("OnEnterPressed", function(self)
        ApplyEditBoxValue()
        self:ClearFocus()
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        ApplyEditBoxValue()
    end)
    eb:SetScript("OnEscapePressed", function(self)
        local cur = slider:GetValue() or minVal
        if slider.step and slider.step >= 1 then
            cur = math.floor(cur + 0.5)
        end
        self:SetText(tostring(cur))
        self:ClearFocus()
    end)

    -- Minus button (left)
    local minus = CreateFrame("Button", name .. "Minus", parent)
    minus:SetPoint("RIGHT", eb, "LEFT", -2, 0)
    slider.minusButton = minus

    minus:SetScript("OnClick", function()
        local cur = slider:GetValue()
        local st  = slider.step or 1
        local nv  = cur - st
        if nv < slider.minVal then nv = slider.minVal end
        slider:SetValue(nv)
    end)

    MSUF_StyleSmallButton(minus, false) -- Midnight minus

    -- Plus button (right)
    local plus = CreateFrame("Button", name .. "Plus", parent)
    plus:SetPoint("LEFT", eb, "RIGHT", 2, 0)
    slider.plusButton = plus

    plus:SetScript("OnClick", function()
        local cur = slider:GetValue()
        local st  = slider.step or 1
        local nv  = cur + st
        if nv > slider.maxVal then nv = slider.maxVal end
        slider:SetValue(nv)
    end)

    MSUF_StyleSmallButton(plus, true) -- Midnight plus

    -- Slider callback + sync with edit box
    slider:SetScript("OnValueChanged", function(self, value)
        local step = self.step or 1
        local formatted

        if step >= 1 then
            value     = math.floor(value + 0.5)
            formatted = tostring(value)
        else
            local precision  = 2
            local multiplier = 10 ^ precision
            value     = math.floor(value * multiplier + 0.5) / multiplier
            formatted = string.format("%." .. precision .. "f", value)
        end

        if self.editBox and not self.editBox:HasFocus() then
            local cur = self.editBox:GetText()
            if cur ~= formatted then
                self.editBox:SetText(formatted)
            end
        end

        if self.onValueChanged then
            self.onValueChanged(self, value)
        end
    end)

    -- Midnight look for the slider itself
    MSUF_StyleSlider(slider)

    return slider
end
local function CreateLabeledCheckButton(name, label, parent, x, y)
        local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")

        local extraY = 0
        if parent == frameGroup or parent == fontGroup or parent == barGroup or parent == profileGroup then
            extraY = -40
        end

        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y + extraY)
        cb.text = _G[name .. "Text"]
        cb.text:SetText(label)
        return cb
    end
    --------------------------------------------------
    -- FRAME GROUP: WIDTH/HEIGHT/OFFSETS + VISIBILITY
    --------------------------------------------------
    widthSlider = CreateLabeledSlider(
        "MSUF_WidthSlider", "Width", frameGroup,
        20, 999, 1,
        16, -90
    )

    heightSlider = CreateLabeledSlider(
        "MSUF_HeightSlider", "Height", frameGroup,
        20, 999, 1,
        16, -140
    )

    xSlider = CreateLabeledSlider(
        "MSUF_OffsetXSlider", "Offset X", frameGroup,
        -999, 999, 1,
        16, -190
    )

    ySlider = CreateLabeledSlider(
        "MSUF_OffsetYSlider", "Offset Y", frameGroup,
        -999, 999, 1,
        16, -240
    )

    -- Slider for boss frame spacing (only used on the Boss Frames tab)
    bossSpacingSlider = CreateLabeledSlider(
        "MSUF_BossSpacingSlider", "Boss spacing", frameGroup,
        -200, 0, 1,
        32, -350
    )
    bossSpacingSlider.onValueChanged = function(self, value)
    EnsureDB()
    MSUF_DB.boss = MSUF_DB.boss or {}
    MSUF_DB.boss.spacing = value

    -- Bossframes neu positionieren
    ApplySettingsForKey("boss")
end


    -- X/Y sliders are created for internal syncing, but fully hidden in the UI
    if xSlider then
        xSlider:Hide()
        if xSlider.editBox then xSlider.editBox:Hide() end
        if xSlider.minusButton then xSlider.minusButton:Hide() end
        if xSlider.plusButton then xSlider.plusButton:Hide() end
    end
    if ySlider then
        ySlider:Hide()
        if ySlider.editBox then ySlider.editBox:Hide() end
        if ySlider.minusButton then ySlider.minusButton:Hide() end
        if ySlider.plusButton then ySlider.plusButton:Hide() end
    end

    showNameCB = CreateLabeledCheckButton(
        "MSUF_ShowNameCheck", "Show name", frameGroup,
        16, -290
    )

    showHPCB = CreateLabeledCheckButton(
        "MSUF_ShowHPCheck", "Show HP text", frameGroup,
        16, -330
    )

    showPowerCB = CreateLabeledCheckButton(
        "MSUF_ShowPowerCheck", "Show power text", frameGroup,
        16, -370
    )

    enableFrameCB = CreateLabeledCheckButton(
        "MSUF_EnableFrameCheck", "Enable this frame", frameGroup,
        16, -410
    )

   
    

 -- Anchor settings (global, aber im Frame-Tab sichtbar)
    anchorLabel = frameGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    anchorLabel:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", 300, -390)
    anchorLabel:SetText("Anchor frame (global name)")

    anchorEdit = CreateFrame("EditBox", "MSUF_AnchorEditBox", frameGroup, "InputBoxTemplate")
    anchorEdit:SetSize(180, 20)
    anchorEdit:SetAutoFocus(false)
    anchorEdit:SetPoint("TOPLEFT", anchorLabel, "BOTTOMLEFT", 0, -2)
    anchorLabel:Hide()
    anchorEdit:Hide()
anchorEdit:EnableMouse(false)


    local function ApplyAnchorEditBox()
        EnsureDB()
        txt = anchorEdit:GetText() or ""
        if txt == "" then
            txt = "UIParent"
        end
        MSUF_DB.general.anchorName = txt
        ApplyAllSettings()
    end

    anchorEdit:SetScript("OnEnterPressed", function(self)
        ApplyAnchorEditBox()
        self:ClearFocus()
    end)
    anchorEdit:SetScript("OnEditFocusLost", function(self)
        ApplyAnchorEditBox()
    end)

    -- anchorCheck for "Anchor all unitframes to Cooldown Manager" removed.
    -- This toggle now only exists in the MSUF Edit Mode panel.
    --------------------------------------------------
    -- TEXT OFFSETS (Frame group)
    --------------------------------------------------
    panel.nameOffsetXSlider = CreateLabeledSlider(
        "MSUF_NameOffsetXSlider", "Name offset X", frameGroup,
        -999, 999, 1,
        300, -110
    )

    panel.nameOffsetYSlider = CreateLabeledSlider(
        "MSUF_NameOffsetYSlider", "Name offset Y", frameGroup,
        -999, 999, 1,
        300, -180
    )

    panel.hpOffsetXSlider = CreateLabeledSlider(
        "MSUF_HPOffsetXSlider", "HP text offset X", frameGroup,
        -999, 999, 1,
        300, -250
    )

    panel.hpOffsetYSlider = CreateLabeledSlider(
        "MSUF_HPOffsetYSlider", "HP text offset Y", frameGroup,
        -999, 999, 1,
        300, -320
    )

    panel.powerOffsetXSlider = CreateLabeledSlider(
        "MSUF_PowerOffsetXSlider", "Power text offset X", frameGroup,
        -999, 999, 1,
        300, -390
    )

    panel.powerOffsetYSlider = CreateLabeledSlider(
        "MSUF_PowerOffsetYSlider", "Power text offset Y", frameGroup,
        -999, 999, 1,
        300, -460
    )

    --------------------------------------------------
    
    --------------------------------------------------
    -- PROFILES TAB: Simple profile UI + import/export
    --------------------------------------------------

    -- Popup: Bestätigung zum Zurücksetzen eines Profils
    StaticPopupDialogs["MSUF_CONFIRM_RESET_PROFILE"] = {
        text = "Do you really want to reset the profile '%s' to defaults?\n\nThis cannot be undone.",
        button1 = YES,
        button2 = NO,
        OnAccept = function(self, data)
            if data and data.name and data.panel then
                -- Profil auf Defaults zurücksetzen
                MSUF_ResetProfile(data.name)

                -- Optionen neu aus der DB laden, damit alles in der UI aktualisiert wird
                if data.panel.LoadFromDB then
                    data.panel:LoadFromDB()
                end
                if data.panel.UpdateProfileUI then
                    data.panel:UpdateProfileUI(data.name)
                end
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    -- Popup: Bestätigung zum Löschen eines Profils
    StaticPopupDialogs["MSUF_CONFIRM_DELETE_PROFILE"] = {
        text = "Are you sure you want to delete '%s'?",
        button1 = YES,
        button2 = NO,
        OnAccept = function(self, data)
            if data and data.name and data.panel then
                -- Profil wirklich löschen
                MSUF_DeleteProfile(data.name)
                -- UI aktualisieren (Dropdown + Label)
                data.panel:UpdateProfileUI(MSUF_ActiveProfile)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
      profileTitle = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    profileTitle:SetPoint("TOPLEFT", profileGroup, "TOPLEFT", 16, -140)
    profileTitle:SetText("Profiles")

    -- Reset + Current profile
    resetBtn = CreateFrame("Button", "MSUF_ProfileResetButton", profileGroup, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 24)
    resetBtn:SetPoint("TOPLEFT", profileTitle, "BOTTOMLEFT", 0, -10)
    resetBtn:SetText("Reset profile")

    -- ✨ Hier kommt jetzt die Logik für den Klick
    resetBtn:SetScript("OnClick", function()
        if not MSUF_ActiveProfile then
            return
        end

        -- Aktives Profil auf Defaults zurücksetzen
        MSUF_ResetProfile(MSUF_ActiveProfile)

        -- Optionen aus der DB neu laden, damit alle Slider/Checks updated sind
        if panel.LoadFromDB then
            panel:LoadFromDB()
        end
        if panel.UpdateProfileUI then
            panel:UpdateProfileUI(MSUF_ActiveProfile)
        end
    end)
    -- Klick-Logik für Reset mit Bestätigungsfenster
    resetBtn:SetScript("OnClick", function()
        if not MSUF_ActiveProfile then
            print("|cffff0000MSUF:|r No active profile selected to reset.")
            return
        end

        local name = MSUF_ActiveProfile

        StaticPopup_Show(
            "MSUF_CONFIRM_RESET_PROFILE",
            name,   -- ersetzt %s im Text
            nil,
            {
                name  = name,   -- geht an data.name im Popup
                panel = panel,  -- geht an data.panel -> LoadFromDB/UpdateProfileUI
            }
        )
    end)
    currentProfileLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    currentProfileLabel:SetPoint("LEFT", resetBtn, "RIGHT", 12, 0)
    currentProfileLabel:SetText("Current profile: Default")


    -- Reset + Current profile
    resetBtn = CreateFrame("Button", "MSUF_ProfileResetButton", profileGroup, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 24)
    resetBtn:SetPoint("TOPLEFT", profileTitle, "BOTTOMLEFT", 0, -10)
    resetBtn:SetText("Reset profile")

    currentProfileLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    currentProfileLabel:SetPoint("LEFT", resetBtn, "RIGHT", 12, 0)
    currentProfileLabel:SetText("Current profile: Default")

deleteBtn = CreateFrame("Button", "MSUF_ProfileDeleteButton", profileGroup, "UIPanelButtonTemplate")
deleteBtn:SetSize(140, 24)
deleteBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
deleteBtn:SetText("Delete profile")
    -- Begrenze den Profilnamen zwischen Reset- und Delete-Button
    currentProfileLabel:SetPoint("RIGHT", deleteBtn, "LEFT", -8, 0)
    currentProfileLabel:SetJustifyH("LEFT")
    currentProfileLabel:SetWordWrap(false)


    helpText = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -8)
    helpText:SetWidth(540)
    helpText:SetJustifyH("LEFT")
    helpText:SetText("Profiles are global. Each character selects one active profile. Create a new profile on the left or select an existing one on the right.")

    --------------------------------------------------
    -- New / Existing row
    --------------------------------------------------
    newLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    newLabel:SetPoint("TOPLEFT", helpText, "BOTTOMLEFT", 0, -14)
    newLabel:SetText("New")

    existingLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    existingLabel:SetPoint("LEFT", newLabel, "LEFT", 260, 0)
    existingLabel:SetText("Existing profiles")

    -- New profile editbox
    newEditBox = CreateFrame("EditBox", "MSUF_ProfileNewEdit", profileGroup, "InputBoxTemplate")
    newEditBox:SetSize(220, 20)
    newEditBox:SetAutoFocus(false)
    newEditBox:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 0, -4)

    -- Existing profiles dropdown
    profileDrop = CreateFrame("Frame", "MSUF_ProfileDropdown", profileGroup, "UIDropDownMenuTemplate")
    profileDrop:SetPoint("TOPLEFT", existingLabel, "BOTTOMLEFT", -16, -4)

    local function MSUF_ProfileDropdown_Initialize(self, level)
        if not level then return end
        profiles = MSUF_GetAllProfiles()
        for _, name in ipairs(profiles) do
            info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.value = name
            info.func = function(btn)
                UIDropDownMenu_SetSelectedValue(self, btn.value)
                UIDropDownMenu_SetText(self, btn.value)
                MSUF_SwitchProfile(btn.value)
                currentProfileLabel:SetText("Current profile: " .. btn.value)
            end
            info.checked = (name == MSUF_ActiveProfile)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(profileDrop, MSUF_ProfileDropdown_Initialize)
    UIDropDownMenu_SetWidth(profileDrop, 180)
    UIDropDownMenu_SetText(profileDrop, MSUF_ActiveProfile or "Default")

    -- Helper to refresh UI from outside if needed
    function panel:UpdateProfileUI(currentName)
        name = currentName or MSUF_ActiveProfile or "Default"
        currentProfileLabel:SetText("Current profile: " .. name)
        UIDropDownMenu_SetSelectedValue(profileDrop, name)
        UIDropDownMenu_SetText(profileDrop, name)
    end

    -- Neues Profil per Enter erstellen
    newEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        name = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            MSUF_CreateProfile(name)
            MSUF_SwitchProfile(name)
            self:SetText("")
            panel:UpdateProfileUI(name)
        end
    end)

deleteBtn:SetScript("OnClick", function()
    if not MSUF_ActiveProfile then
        return
    end

    name = MSUF_ActiveProfile

    -- Optional: 'Default' extra schützen
    if name == "Default" then
        print("|cffff0000MSUF:|r Das 'Default'-Thanks for testing and reporting bugs no you can not delete Default'.")
        return
    end

    -- Warn-Popup anzeigen: '%s' wird durch name ersetzt
    StaticPopup_Show(
        "MSUF_CONFIRM_DELETE_PROFILE",
        name,       -- ersetzt %s im Text
        nil,
        {
            name  = name,   -- geht an data.name im Popup
            panel = panel,  -- geht an data.panel -> für UpdateProfileUI
        }
    )
end)


    --------------------------------------------------
    -- IMPORT / EXPORT BLOCK
    --------------------------------------------------
    profileLine = profileGroup:CreateTexture(nil, "ARTWORK")
    profileLine:SetColorTexture(1, 1, 1, 0.18)
    profileLine:SetPoint("TOPLEFT", newEditBox, "BOTTOMLEFT", 0, -20)
    profileLine:SetSize(540, 1)

    importTitle = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    importTitle:SetPoint("TOPLEFT", profileLine, "BOTTOMLEFT", 0, -10)
    importTitle:SetText("Profile export / import")

    scroll = CreateFrame("ScrollFrame", "MSUF_ProfileScroll", profileGroup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", importTitle, "BOTTOMLEFT", 0, -10)
    scroll:SetSize(540, 180)

    editBox = CreateFrame("EditBox", "MSUF_ProfileEditBox", scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(520)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(editBox)

    exportBtn = CreateFrame("Button", nil, profileGroup, "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 22)
    exportBtn:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -5)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        str = MSUF_SerializeDB()
        editBox:SetText(str)
        editBox:HighlightText()
        print("|cff00ff00MSUF:|r Profile exported to text box.")
    end)

    importBtn = CreateFrame("Button", nil, profileGroup, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        str = editBox:GetText()
        MSUF_ImportFromString(str)
        ApplyAllSettings()
        UpdateAllFonts()
        panel:LoadFromDB()
        panel:UpdateProfileUI(MSUF_ActiveProfile)
    end)

    --------------------------------------------------
    -- FONT GROUP: Font-Dropdown & globale Font-Optionen
    --------------------------------------------------
    fontTitle = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fontTitle:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 16, -140)

--------------------------------------------------
-- FONT GROUP: Global font + Font color & style (like Bars menu)
--------------------------------------------------

-- LEFT COLUMN HEADER + LINE
globalFontHeader = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
globalFontHeader:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 16, -140)
globalFontHeader:SetText("Global font")

globalFontLine = fontGroup:CreateTexture(nil, "ARTWORK")
globalFontLine:SetColorTexture(1, 1, 1, 0.2)
globalFontLine:SetSize(220, 1)
globalFontLine:SetPoint("TOPLEFT", globalFontHeader, "BOTTOMLEFT", 0, -4)

-- RIGHT COLUMN HEADER + LINE
fontColorHeader = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
fontColorHeader:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 276, -140)
fontColorHeader:SetText("Font color & style")

fontColorLine = fontGroup:CreateTexture(nil, "ARTWORK")
fontColorLine:SetColorTexture(1, 1, 1, 0.2)
fontColorLine:SetSize(260, 1)
fontColorLine:SetPoint("TOPLEFT", fontColorHeader, "BOTTOMLEFT", 0, -4)

--------------------------------------------------
-- FONT DROPDOWN (LEFT)
--------------------------------------------------
fontDrop = CreateFrame("Frame", "MSUF_FontDropdown", fontGroup, "UIDropDownMenuTemplate")
fontDrop:SetPoint("TOPLEFT", globalFontLine, "BOTTOMLEFT", -16, -8)

fontColorDrop = CreateFrame("Frame", "MSUF_FontColorDropdown", fontGroup, "UIDropDownMenuTemplate")
fontColorDrop:SetPoint("TOPLEFT", fontColorLabel, "BOTTOMLEFT", -16, -8)

    -- Liste der verfügbaren Fonts (interne + LSM)
    fontChoices = {}

    local function MSUF_RebuildFontChoices()
        fontChoices = {}

        -- 1) interne Fallback-Fonts aus FONT_LIST
        for _, info in ipairs(FONT_LIST) do
            table.insert(fontChoices, {
                key   = info.key,   -- z.B. "EXPRESSWAY"
                label = info.name,  -- z.B. "Expressway (addon)"
            })
        end

        -- 2) LibSharedMedia-Fonts anhängen, falls vorhanden
        if LSM then
            names = LSM:List("font")
            table.sort(names)

            used = {}
            for _, e in ipairs(fontChoices) do
                used[e.key] = true   -- nach KEY deduplizieren
            end

            for _, name in ipairs(names) do
                if not used[name] then
                    table.insert(fontChoices, {
                        key   = name,  -- Key, den LSM:Fetch erwartet
                        label = name,  -- so steht es im Dropdown
                    })
                    used[name] = true
                end
            end
        end
    end

    -- einmal initial aufbauen
    MSUF_RebuildFontChoices()

local function FontDropdown_Initialize(self, level)
    EnsureDB()

    -- falls LSM Fonts nachträglich registriert wurden
    if not fontChoices or #fontChoices == 0 then
        MSUF_RebuildFontChoices()
    end

    info = UIDropDownMenu_CreateInfo()
    currentKey = MSUF_DB.general.fontKey

    for _, data in ipairs(fontChoices) do
        -- WICHTIG: pro Eintrag eigene Upvalues
        local thisKey   = data.key
        local thisLabel = data.label

        info.text       = thisLabel
        info.value      = thisKey

        -- Vorschau-Font für diese Zeile
        info.fontObject = MSUF_GetFontPreviewObject(thisKey)

        info.func = function()
            EnsureDB()
            MSUF_DB.general.fontKey = thisKey

            UIDropDownMenu_SetSelectedValue(fontDrop, thisKey)
            UIDropDownMenu_SetText(fontDrop, thisLabel)

            -- sofort anwenden
            UpdateAllFonts()

            -- falls SharedMedia erst im nächsten Frame greift
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    UpdateAllFonts()
                end)
            end
        end

        info.checked = (currentKey == thisKey)
        UIDropDownMenu_AddButton(info, level)
    end
end
    UIDropDownMenu_Initialize(fontDrop, FontDropdown_Initialize)
    UIDropDownMenu_SetWidth(fontDrop, 180)
    do
        currentKey = MSUF_DB.general.fontKey
        currentLabel = currentKey
        for _, data in ipairs(fontChoices) do
            if data.key == currentKey then
                currentLabel = data.label
                break
            end
        end
        UIDropDownMenu_SetSelectedValue(fontDrop, currentKey)
        UIDropDownMenu_SetText(fontDrop, currentLabel)
    end
    --------------------------------------------------
-- FONT COLOR DROPDOWN
--------------------------------------------------
fontColorLabel = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
fontColorLabel:SetPoint("TOPLEFT", fontColorLine, "BOTTOMLEFT", 0, -8)

fontColorDrop:SetPoint("TOPLEFT", fontColorLabel, "BOTTOMLEFT", -16, -4)

-- 15 NICE COLORS
MSUF_COLOR_LIST = {
    { key = "white",     r=1,   g=1,   b=1,   label="White" },
    { key = "black",     r=0,   g=0,   b=0,   label="Black" },
    { key = "red",       r=1,   g=0,   b=0,   label="Red" },
    { key = "green",     r=0,   g=1,   b=0,   label="Green" },
    { key = "blue",      r=0,   g=0,   b=1,   label="Blue" },
    { key = "yellow",    r=1,   g=1,   b=0,   label="Yellow" },
    { key = "cyan",      r=0,   g=1,   b=1,   label="Cyan" },
    { key = "magenta",   r=1,   g=0,   b=1,   label="Magenta" },
    { key = "orange",    r=1,   g=0.5, b=0,   label="Orange" },
    { key = "purple",    r=0.6, g=0,   b=0.8, label="Purple" },
    { key = "pink",      r=1,   g=0.6, b=0.8, label="Pink" },
    { key = "turquoise", r=0,   g=0.9, b=0.8, label="Turquoise" },
    { key = "grey",      r=0.5, g=0.5, b=0.5, label="Grey" },
    { key = "brown",     r=0.6, g=0.3, b=0.1, label="Brown" },
    { key = "gold",      r=1,   g=0.85,b=0.1, label="Gold" },
}

local function FontColorDropdown_Initialize(self, lvl)
    EnsureDB()

    info = UIDropDownMenu_CreateInfo()
    local currentKey = MSUF_DB.general.fontColor or "white"

    for _, c in ipairs(MSUF_COLOR_LIST) do
        -- pro Eintrag eigene Upvalues benutzen
        local thisKey   = c.key
        local thisLabel = c.label

        info.text  = thisLabel
        info.value = thisKey

        info.func = function()
            EnsureDB()
            MSUF_DB.general.fontColor = thisKey

            UIDropDownMenu_SetSelectedValue(fontColorDrop, thisKey)
            UIDropDownMenu_SetText(fontColorDrop, thisLabel) -- Label direkt aktualisieren

            UpdateAllFonts()                                 -- Farben sofort anwenden
        end

        info.checked = (currentKey == thisKey)
        UIDropDownMenu_AddButton(info, lvl)
    end
end


UIDropDownMenu_Initialize(fontColorDrop, FontColorDropdown_Initialize)
UIDropDownMenu_SetWidth(fontColorDrop, 180)
do
    key = (MSUF_DB.general.fontColor or "white")
    label = key
    for _, c in ipairs(MSUF_COLOR_LIST) do
        if c.key == key then
            label = c.label
            break
        end
    end
    UIDropDownMenu_SetSelectedValue(fontColorDrop, key)
    UIDropDownMenu_SetText(fontColorDrop, label)
end

	

        boldCheck = CreateFrame("CheckButton", "MSUF_BoldTextCheck", fontGroup, "UICheckButtonTemplate")
    boldCheck:SetPoint("TOPLEFT", fontColorDrop, "BOTTOMLEFT", 16, -20)
    boldCheck.text = _G["MSUF_BoldTextCheckText"]
    boldCheck.text:SetText("Use bold text (THICKOUTLINE)")

        -- NEW: Toggle to completely disable the black outline
    noOutlineCheck = CreateFrame("CheckButton", "MSUF_NoOutlineCheck", fontGroup, "UICheckButtonTemplate")
    noOutlineCheck:SetPoint("TOPLEFT", boldCheck, "BOTTOMLEFT", 0, -75)
    noOutlineCheck.text = _G["MSUF_NoOutlineCheckText"]
    noOutlineCheck.text:SetText("Disable black outline around text")

    nameClassColorCheck = CreateFrame("CheckButton", "MSUF_NameClassColorCheck", fontGroup, "UICheckButtonTemplate")
    nameClassColorCheck:SetPoint("TOPLEFT", boldCheck, "BOTTOMLEFT", 0, -4)
    nameClassColorCheck.text = _G["MSUF_NameClassColorCheckText"]
    nameClassColorCheck.text:SetText("Color player names by class")

    -- Checkbox: NPC/Boss-Namen rot
    npcNameRedCheck = CreateFrame("CheckButton", "MSUF_NPCNameRedCheck", fontGroup, "UICheckButtonTemplate")
    npcNameRedCheck:SetPoint("TOPLEFT", nameClassColorCheck, "BOTTOMLEFT", 0, -4)
    npcNameRedCheck.text = _G["MSUF_NPCNameRedCheckText"]
    npcNameRedCheck.text:SetText("Color NPC/boss names (friendly white / hostile red)")

    -- Checkbox: shorten names (Abgeschaltet aktuell)
       shortenNamesCheck = CreateFrame("CheckButton", "MSUF_ShortenNamesCheck", fontGroup, "UICheckButtonTemplate")
    -- shortenNamesCheck:SetPoint("TOPLEFT", npcNameRedCheck, "BOTTOMLEFT", 0, -4)
    -- shortenNamesCheck.text = _G["MSUF_ShortenNamesCheckText"]
    -- shortenNamesCheck.text:SetText("Shorten names (max 12 chars) WARNING DOES NOT WORK IN INSTANCES!")

    -- Checkbox: Text-Backdrop / Schatten
    textBackdropCheck = CreateFrame("CheckButton", "MSUF_TextBackdropCheck", fontGroup, "UICheckButtonTemplate")
    textBackdropCheck:SetPoint("TOPLEFT", shortenNamesCheck, "BOTTOMLEFT", 0, -4)
    textBackdropCheck.text = _G["MSUF_TextBackdropCheckText"]
    textBackdropCheck.text:SetText("Add text shadow (backdrop)")

    -- Initialzustand aus der DB
    EnsureDB()
    boldCheck:SetChecked(MSUF_DB.general.boldText and true or false)
    noOutlineCheck:SetChecked(MSUF_DB.general.noOutline and true or false)  -- NEW
    nameClassColorCheck:SetChecked(MSUF_DB.general.nameClassColor and true or false)
    npcNameRedCheck:SetChecked(MSUF_DB.general.npcNameRed and true or false)
    shortenNamesCheck:SetChecked(MSUF_DB.shortenNames and true or false)
    textBackdropCheck:SetChecked(MSUF_DB.general.textBackdrop and true or false)

    -- Toggle: Bold Text ein/aus
    boldCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.boldText = self:GetChecked() and true or false
        UpdateAllFonts()
    end)
        -- Toggle: Outline komplett aus/an
    noOutlineCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.noOutline = self:GetChecked() and true or false
        UpdateAllFonts()
    end)

    -- Toggle: Namen in Klassenfarbe einfärben
    nameClassColorCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.nameClassColor = self:GetChecked() and true or false
        UpdateAllFonts()
    end)

    -- Toggle: NPC/Boss-Namen rot
    npcNameRedCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.npcNameRed = self:GetChecked() and true or false
        UpdateAllFonts()
    end)

    -- Toggle: Namen kürzen (max 12 Zeichen)
    shortenNamesCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.shortenNames = self:GetChecked() and true or false
        ApplyAllSettings()
    end)

    -- Toggle: Text-Backdrop / Schatten
    textBackdropCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.textBackdrop = self:GetChecked() and true or false
        UpdateAllFonts()
    end)

    --------------------------------------------------
    -- TEXT SIZE HEADER + LINE
    --------------------------------------------------
    textSizeHeader = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    textSizeHeader:SetPoint("TOPLEFT", fontDrop, "BOTTOMLEFT", 16, -40)
    textSizeHeader:SetText("Text sizes")

    textSizeLine = fontGroup:CreateTexture(nil, "ARTWORK")
    textSizeLine:SetColorTexture(1, 1, 1, 0.2)
    textSizeLine:SetSize(220, 1)
    textSizeLine:SetPoint("TOPLEFT", textSizeHeader, "BOTTOMLEFT", -16, -4)

    --------------------------------------------------
    -- PER-ELEMENT FONT SIZE SLIDERS
    --------------------------------------------------
    nameFontSizeSlider = CreateLabeledSlider(
        "MSUF_NameFontSizeSlider", "Name text size", fontGroup,
        8, 32, 1,
        16, -250
    )
    nameFontSizeSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.nameFontSize = math.floor(value + 0.5)
        UpdateAllFonts()
    end

    hpFontSizeSlider = CreateLabeledSlider(
        "MSUF_HPFontSizeSlider", "Health text size", fontGroup,
        8, 32, 1,
        16, -320
    )

    hpFontSizeSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.hpFontSize = math.floor(value + 0.5)
        UpdateAllFonts()
    end

    powerFontSizeSlider = CreateLabeledSlider(
        "MSUF_PowerFontSizeSlider", "Power text size", fontGroup,
        8, 32, 1,
        16, -390
    )

    powerFontSizeSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.powerFontSize = math.floor(value + 0.5)
        UpdateAllFonts()
    end
    -- Castbar Spellname Font Size (aus Castbar-Menü hierher verschoben)
    castbarSpellNameFontSizeSlider = CreateLabeledSlider(
        "MSUF_CastbarSpellNameFontSizeSlider",
        "Castbar spell name size",
        fontGroup,
        0, 30, 1,
        16, -460
    )
    castbarSpellNameFontSizeSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarSpellNameFontSize = value
        -- nur Castbars neu bauen
        MSUF_UpdateCastbarVisuals()
    end

    --------------------------------------------------
    -- MISC TAB (Mouseover Highlight)
    --------------------------------------------------
    miscTitle = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    miscTitle:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 16, -120)
        -- Linke Spalte: Mouseover & Updates
    miscLeftHeader = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    miscLeftHeader:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 16, -160)
    miscLeftHeader:SetText("Mouseover & updates")

    miscLeftLine = miscGroup:CreateTexture(nil, "ARTWORK")
    miscLeftLine:SetColorTexture(1, 1, 1, 0.2)
    miscLeftLine:SetSize(320, 1)
    miscLeftLine:SetPoint("TOPLEFT", miscLeftHeader, "BOTTOMLEFT", -16, -4)

    -- Rechte Spalte: Unit info panel
    miscRightHeader = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    miscRightHeader:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 420, -160)
    miscRightHeader:SetText("Unit info panel")

    miscRightLine = miscGroup:CreateTexture(nil, "ARTWORK")
    miscRightLine:SetColorTexture(1, 1, 1, 0.2)
    miscRightLine:SetSize(260, 1)
    miscRightLine:SetPoint("TOPLEFT", miscRightHeader, "BOTTOMLEFT", -16, -4)


    highlightEnableCheck = CreateFrame("CheckButton", "MSUF_HighlightEnableCheck", miscGroup, "UICheckButtonTemplate")
    highlightEnableCheck:SetPoint("TOPLEFT", miscLeftLine, "BOTTOMLEFT", 16, -16)
    highlightEnableCheck.text = _G["MSUF_HighlightEnableCheckText"] or highlightEnableCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    highlightEnableCheck.text:SetPoint("LEFT", highlightEnableCheck, "RIGHT", 2, 0)
    highlightEnableCheck.text:SetText("Enable mouseover highlight")

    highlightEnableCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.highlightEnabled = self:GetChecked() and true or false
        UpdateAllHighlightColors()
    end)

    highlightColorLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    highlightColorLabel:SetPoint("TOPLEFT", highlightEnableCheck, "BOTTOMLEFT", 0, -12)
    highlightColorLabel:SetText("Mouseover highlight color")

    highlightColorDrop = CreateFrame("Frame", "MSUF_HighlightColorDropdown", miscGroup, "UIDropDownMenuTemplate")
    highlightColorDrop:SetPoint("TOPLEFT", highlightColorLabel, "BOTTOMLEFT", -16, -4)

    local function HighlightColorDropdown_Initialize(self, level)
        EnsureDB()
        g = MSUF_DB.general or {}
        current = (type(g.highlightColor) == "string" and g.highlightColor:lower()) or "white"

        info = UIDropDownMenu_CreateInfo()
        for _, opt in ipairs(MSUF_COLOR_LIST) do
            info.text    = opt.label
            info.value   = opt.key
            info.checked = (opt.key == current)
            info.func    = function(button)
                EnsureDB()
                val = button.value or opt.key
                -- Farb-Key im SavedVariable speichern
                MSUF_DB.general.highlightColor = val
                -- Dropdown-Text sofort aktualisieren
                UIDropDownMenu_SetSelectedValue(highlightColorDrop, val)
                -- Alle bestehenden Frames neu einfärben
                UpdateAllHighlightColors()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(highlightColorDrop, HighlightColorDropdown_Initialize)
    UIDropDownMenu_SetWidth(highlightColorDrop, 180)

    -- Global unit update interval for unit frame event updates
    updateThrottleLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    updateThrottleLabel:SetPoint("TOPLEFT", highlightColorDrop, "BOTTOMLEFT", 16, -20)
    updateThrottleLabel:SetText("Unit update interval (seconds)")

    updateThrottleSlider = CreateFrame("Slider", "MSUF_UpdateIntervalSlider", miscGroup, "OptionsSliderTemplate")
    updateThrottleSlider:SetPoint("TOPLEFT", updateThrottleLabel, "BOTTOMLEFT", 0, -8)
    updateThrottleSlider:SetMinMaxValues(0.01, 0.30)
    updateThrottleSlider:SetValueStep(0.01)
    updateThrottleSlider:SetObeyStepOnDrag(true)
    updateThrottleSlider:SetWidth(200)

    _G[updateThrottleSlider:GetName() .. "Low"]:SetText("0.01")
    _G[updateThrottleSlider:GetName() .. "High"]:SetText("0.30")

    updateThrottleSlider:SetScript("OnShow", function(self)
        EnsureDB()
        v = MSUF_DB.general and MSUF_DB.general.frameUpdateInterval or MSUF_FrameUpdateInterval or 0.05
        if type(v) ~= "number" then v = 0.05 end
        if v < 0.01 then v = 0.01 elseif v > 0.30 then v = 0.30 end
        self:SetValue(v)
    end)

    updateThrottleSlider:SetScript("OnValueChanged", function(self, value)
        EnsureDB()
        v = tonumber(value) or 0.05
        if v < 0.01 then v = 0.01 elseif v > 0.30 then v = 0.30 end
        MSUF_DB.general.frameUpdateInterval = v
        MSUF_FrameUpdateInterval = v
    end)

    -- Castbar update interval (seconds)
    MSUF_CastbarUpdateLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    MSUF_CastbarUpdateLabel:SetPoint("TOPLEFT", updateThrottleLabel, "BOTTOMLEFT", 0, -40)
    MSUF_CastbarUpdateLabel:SetText("Castbar update")

    MSUF_CastbarUpdateIntervalSlider = CreateFrame("Slider", "MSUF_CastbarUpdateIntervalSlider", miscGroup, "OptionsSliderTemplate")
    MSUF_CastbarUpdateIntervalSlider:SetPoint("TOPLEFT", MSUF_CastbarUpdateLabel, "BOTTOMLEFT", 0, -8)
    MSUF_CastbarUpdateIntervalSlider:SetMinMaxValues(0.01, 0.30)
    MSUF_CastbarUpdateIntervalSlider:SetValueStep(0.01)
    MSUF_CastbarUpdateIntervalSlider:SetObeyStepOnDrag(true)
    MSUF_CastbarUpdateIntervalSlider:SetWidth(200)
    _G[MSUF_CastbarUpdateIntervalSlider:GetName() .. "Low"]:SetText("0.01")
    _G[MSUF_CastbarUpdateIntervalSlider:GetName() .. "High"]:SetText("0.30")

    MSUF_CastbarUpdateIntervalSlider:SetScript("OnShow", function(self)
        EnsureDB()
        v = MSUF_DB.general and MSUF_DB.general.castbarUpdateInterval or MSUF_CastbarUpdateInterval or 0.02
        self:SetValue(v)
        _G[self:GetName() .. "Text"]:SetText(string.format("%.2f", v))
    end)

    MSUF_CastbarUpdateIntervalSlider:SetScript("OnValueChanged", function(self, value)
        EnsureDB()
        v = tonumber(value) or 0.02
        if v < 0.01 then v = 0.01 elseif v > 0.30 then v = 0.30 end
        MSUF_DB.general.castbarUpdateInterval = v
        MSUF_CastbarUpdateInterval = v
        _G[self:GetName() .. "Text"]:SetText(string.format("%.2f", v))
    end)


    --------------------------------------------------
    -- Absorb overlay toggle (white bar on HP-Bar)
    --------------------------------------------------
    local absorbBarCheck = CreateFrame("CheckButton", "MSUF_AbsorbBarCheck", miscGroup, "UICheckButtonTemplate")
    absorbBarCheck:SetPoint("TOPLEFT", MSUF_CastbarUpdateIntervalSlider, "BOTTOMLEFT", 0, -24)
    absorbBarCheck.text = _G["MSUF_AbsorbBarCheckText"] or absorbBarCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    absorbBarCheck.text:SetPoint("LEFT", absorbBarCheck, "RIGHT", 2, 0)
    absorbBarCheck.text:SetText("Show absorb overlay (white bar)")

    absorbBarCheck:SetScript("OnShow", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        self:SetChecked(g.enableAbsorbBar ~= false)
    end)

    absorbBarCheck:SetScript("OnClick", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        g.enableAbsorbBar = self:GetChecked() and true or false

        -- Sofort auf alle Frames anwenden
        if UnitFrames then
            for _, frame in pairs(UnitFrames) do
                if frame.absorbBar and frame.unit then
                    if g.enableAbsorbBar == false then
                        frame.absorbBar:SetMinMaxValues(0, 1)
                        frame.absorbBar:SetValue(0)
                        frame.absorbBar:Hide()
                    else
                        local maxHP = UnitHealthMax(frame.unit)
                        MSUF_UpdateAbsorbBar(frame, frame.unit, maxHP)
                    end
                end
            end
        end
    end)

    -- Leader/assist icon toggle
    local leaderIconCheck = CreateFrame("CheckButton", "MSUF_LeaderIconCheck", miscGroup, "UICheckButtonTemplate")
    leaderIconCheck:SetPoint("TOPLEFT", absorbBarCheck, "BOTTOMLEFT", 0, -8)
    leaderIconCheck.text = leaderIconCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    leaderIconCheck.text:SetPoint("LEFT", leaderIconCheck, "RIGHT", 2, 0)
    leaderIconCheck.text:SetText("Show leader/assist icon (player/target)")

    leaderIconCheck:SetScript("OnShow", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        self:SetChecked(g.showLeaderIcon ~= false)
    end)

    leaderIconCheck:SetScript("OnClick", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        g.showLeaderIcon = self:GetChecked() and true or false

        -- Apply immediately to all existing frames
        if UnitFrames then
            for _, frame in pairs(UnitFrames) do
                if frame.leaderIcon and frame.unit then
                    if g.showLeaderIcon == false then
                        frame.leaderIcon:Hide()
                    else
                        if UnitIsGroupLeader and UnitIsGroupLeader(frame.unit) then
                            frame.leaderIcon:Show()
                        else
                            frame.leaderIcon:Hide()
                        end
                    end
                end
            end
        end
    end)

-- Disable custom unit info tooltip panel (player/target/focus/ToT/pet/boss)
infoTooltipDisableCheck = CreateFrame("CheckButton", "MSUF_InfoTooltipDisableCheck", miscGroup, "UICheckButtonTemplate")
-- erster Anker: direkt unter der rechten Trennlinie
infoTooltipDisableCheck:SetPoint("TOPLEFT", miscRightLine, "BOTTOMLEFT", 16, -16)

infoTooltipDisableCheck.text = infoTooltipDisableCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
infoTooltipDisableCheck.text:SetPoint("LEFT", infoTooltipDisableCheck, "RIGHT", 2, 0)
infoTooltipDisableCheck.text:SetText("Disable MSUF unit info panel tooltips")


    infoTooltipDisableCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.disableUnitInfoTooltips = self:GetChecked() and true or false
    end)

    infoTooltipDisableCheck:SetScript("OnShow", function(self)
        EnsureDB()
        g = MSUF_DB.general or {}
        self:SetChecked(g.disableUnitInfoTooltips and true or false)
    end)


    -- Unit info tooltip position
    infoTooltipPosLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    infoTooltipPosLabel:SetPoint("TOPLEFT", infoTooltipDisableCheck, "BOTTOMLEFT", 0, -16)
    infoTooltipPosLabel:SetText("MSUF unit info panel position")

    infoTooltipPosDrop = CreateFrame("Frame", "MSUF_InfoTooltipPosDropdown", miscGroup, "UIDropDownMenuTemplate")
    infoTooltipPosDrop:SetPoint("TOPLEFT", infoTooltipPosLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(infoTooltipPosDrop, 180)

    local function InfoTooltipPosDropdown_OnClick(self)
        EnsureDB()
        UIDropDownMenu_SetSelectedValue(infoTooltipPosDrop, self.value)
        MSUF_DB.general.unitInfoTooltipStyle = self.value
    end

    local function InfoTooltipPosDropdown_Initialize(self, level)
        EnsureDB()
        g = MSUF_DB.general or {}
        current = g.unitInfoTooltipStyle or "classic"

        info = UIDropDownMenu_CreateInfo()
        info.func = InfoTooltipPosDropdown_OnClick

        info.text = "Blizzard Classic"
        info.value = "classic"
        info.checked = (current == "classic")
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.func = InfoTooltipPosDropdown_OnClick
        info.text = "Modern (under cursor)"
        info.value = "modern"
        info.checked = (current == "modern")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(infoTooltipPosDrop, InfoTooltipPosDropdown_Initialize)

    infoTooltipPosDrop:SetScript("OnShow", function(self)
        EnsureDB()
        g = MSUF_DB.general or {}
        current = g.unitInfoTooltipStyle or "classic"
        UIDropDownMenu_SetSelectedValue(self, current)
        if current == "modern" then
            UIDropDownMenu_SetText(self, "Modern (under cursor)")
        else
            UIDropDownMenu_SetText(self, "Blizzard Classic")
        end
    end)

    --------------------------------------------------
    -- Blizzard Unitframes Kill Toggle
    --------------------------------------------------
    blizzUFCheck = CreateFrame("CheckButton", "MSUF_DisableBlizzUFCheck", miscGroup, "UICheckButtonTemplate")
    blizzUFCheck:SetPoint("TOPLEFT", infoTooltipPosDrop, "BOTTOMLEFT", 16, -24)

    blizzUFCheck.text = blizzUFCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    blizzUFCheck.text:SetPoint("LEFT", blizzUFCheck, "RIGHT", 0, 0)
    blizzUFCheck.text:SetText("Disable Blizzard unitframes")

    blizzUFCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.disableBlizzardUnitFrames = self:GetChecked() and true or false
        print("|cffffd700MSUF:|r Changing Blizzard unitframes visibility requires a /reload.")
    end)

    blizzUFCheck:SetScript("OnShow", function(self)
        EnsureDB()
        g = MSUF_DB.general or {}
        -- Standard = AN, nur wenn explizit false, dann AUS
        self:SetChecked(g.disableBlizzardUnitFrames ~= false)
    end)
    


    --------------------------------------------------
    -- AURAS TAB (Target aura display)
    --------------------------------------------------
    
    --------------------------------------------------
    -- CASTBAR OPTIONS
    --------------------------------------------------
    
    --------------------------------------------------
    -- Castbar options (Enemy vs Player Sub-Pages)
    --------------------------------------------------    
    -- Timer-Callback für das "Interrupt Feedback" der Player-Castbar
local function MSUF_PlayerCastbar_HideIfNoLongerCasting(timer)
    -- Frame an den Timer hängen (siehe ShowInterruptFeedback)
    self = timer and timer.msuCastbarFrame
    if not self or not self.unit then
        return
    end

    castName = UnitCastingInfo(self.unit)
    chanName = UnitChannelInfo(self.unit)

    -- Wenn wieder ein Cast aktiv ist, normaler Cast-Flow
    if castName or chanName then
        if MSUF_PlayerCastbar_Cast then
            MSUF_PlayerCastbar_Cast(self)
        end
        return
    end

    -- Wenn nichts mehr gecastet wird: Bar ausblenden
    self:SetScript("OnUpdate", nil)
    if self.timeText then
        self.timeText:SetText("")
    end
    self:Hide()
end
    castbarTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    castbarTitle:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -120)
    -- Sub-Menü-Buttons innerhalb des Castbar-Tabs
    -- 1) Target/Focus/Pet (bestehendes Verhalten)
    -- 2) Player (noch leer, Vorbereitung für eigene Optionen)
    castbarEnemyButton = CreateFrame("Button", "MSUF_CastbarEnemyButton", castbarGroup, "UIPanelButtonTemplate")
    castbarEnemyButton:SetSize(80, 22)
    -- Back-Button rechts neben der "Castbar options"-Überschrift
    castbarEnemyButton:SetPoint("LEFT", castbarTitle, "RIGHT", 0, 0)
    castbarEnemyButton:SetText("BACK")

    castbarPlayerButton = CreateFrame("Button", "MSUF_CastbarPlayerButton", castbarGroup, "UIPanelButtonTemplate")
    castbarPlayerButton:SetSize(100, 22)
    -- Player-Button wieder an ungefähr ursprüngliche Position (links unterhalb der Tabs)
    castbarPlayerButton:SetPoint("TOPLEFT", castbarGroup, "BOTTOMLEFT", 17, 450)
    castbarPlayerButton:SetText("Player")



    -- Target Castbar-Subseite
    castbarTargetButton = CreateFrame("Button", "MSUF_CastbarTargetButton", castbarGroup, "UIPanelButtonTemplate")
    castbarTargetButton:SetSize(100, 22)
    -- Direkt rechts neben dem Player-Button
    castbarTargetButton:SetPoint("LEFT", castbarPlayerButton, "RIGHT", 4, 0)
    castbarTargetButton:SetText("Target")


    -- Focus Castbar-Subseite
    castbarFocusButton = CreateFrame("Button", "MSUF_CastbarFocusButton", castbarGroup, "UIPanelButtonTemplate")
    castbarFocusButton:SetSize(100, 22)
    -- Direkt rechts neben dem Target-Button
    castbarFocusButton:SetPoint("LEFT", castbarTargetButton, "RIGHT", 4, 0)
    castbarFocusButton:SetText("Focus")
    local function MSUF_SetActiveCastbarSubPage(page)
        if page == "player" then
            castbarEnemyGroup:Hide()
            castbarTargetGroup:Hide()
            castbarFocusGroup:Hide()
            castbarPlayerGroup:Show()
            castbarEnemyButton:Enable()
            castbarPlayerButton:Disable()
            if castbarTargetButton then castbarTargetButton:Enable() end
            if castbarFocusButton then castbarFocusButton:Enable() end
        elseif page == "target" then
            castbarEnemyGroup:Hide()
            castbarPlayerGroup:Hide()
            castbarFocusGroup:Hide()
            castbarTargetGroup:Show()
            castbarEnemyButton:Enable()
            castbarPlayerButton:Enable()
            if castbarTargetButton then castbarTargetButton:Disable() end
            if castbarFocusButton then castbarFocusButton:Enable() end
        elseif page == "focus" then
            castbarEnemyGroup:Hide()
            castbarTargetGroup:Hide()
            castbarPlayerGroup:Hide()
            castbarFocusGroup:Show()
            castbarEnemyButton:Enable()
            castbarPlayerButton:Enable()
            if castbarTargetButton then castbarTargetButton:Enable() end
            if castbarFocusButton then castbarFocusButton:Disable() end
        else
            -- Standard: Enemy-Optionen (Pet/Allgemein)
            castbarEnemyGroup:Show()
            castbarTargetGroup:Hide()
            castbarFocusGroup:Hide()
            castbarPlayerGroup:Hide()
            castbarEnemyButton:Disable()
            castbarPlayerButton:Enable()
            if castbarTargetButton then castbarTargetButton:Enable() end
            if castbarFocusButton then castbarFocusButton:Enable() end
        end
    end

    castbarEnemyButton:SetScript("OnClick", function()
        MSUF_SetActiveCastbarSubPage("enemy")
    end)

    castbarPlayerButton:SetScript("OnClick", function()
        MSUF_SetActiveCastbarSubPage("player")
    end)

    castbarTargetButton:SetScript("OnClick", function()
        MSUF_SetActiveCastbarSubPage("target")
    end)

    castbarFocusButton:SetScript("OnClick", function()
        MSUF_SetActiveCastbarSubPage("focus")
    end)


        ----------------------------------------------------
    -- Target-Castbar-Untermenü
    --------------------------------------------------
    
    castbarTargetCheck = CreateLabeledCheckButton("MSUF_CastbarTargetCheck", "Enable Target castbar", castbarTargetGroup, 0, -180)
    castbarTargetCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.enableTargetCastbar = self:GetChecked() and true or false
        MSUF_ReanchorTargetCastBar()
    end)
    -- Focus-Castbar-Untermenü: On/Off-Toggle
    castbarFocusCheck = CreateLabeledCheckButton(
        "MSUF_CastbarFocusCheck",
        "Enable Focus castbar",
        castbarFocusGroup,
        0, -180
    )
    castbarFocusCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.enableFocusCastbar = self:GetChecked() and true or false
        MSUF_ReanchorFocusCastBar()
    end)
    -- === General section (left column) ===
    castbarGeneralTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarGeneralTitle:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -170)

    castbarGeneralLine = castbarEnemyGroup:CreateTexture(nil, "ARTWORK")
    castbarGeneralLine:SetColorTexture(1, 1, 1, 0.15)
    castbarGeneralLine:SetHeight(1)
    castbarGeneralLine:SetPoint("TOPLEFT", castbarGeneralTitle, "BOTTOMLEFT", 0, -4)
    castbarGeneralLine:SetPoint("RIGHT", castbarEnemyGroup, "RIGHT", -16, 0)

    -- Checkboxen untereinander in der linken Spalte
    castbarInterruptShakeCheck = CreateLabeledCheckButton(
        "MSUF_CastbarInterruptShakeCheck",
        "Shake on interrupt",
        castbarEnemyGroup,
        16, -200
    )
    castbarInterruptShakeCheck:SetScript("OnClick", function(self)
        EnsureDB()
        -- nil / true = aktiviert, false = aus
        MSUF_DB.general.castbarInterruptShake = self:GetChecked() and true or false
    end)

    castbarIconCheck = CreateLabeledCheckButton(
        "MSUF_CastbarIconCheck",
        "Show icon",
        castbarEnemyGroup,
        16, -230
    )
    castbarIconCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.castbarShowIcon = self:GetChecked() and true or false
        MSUF_UpdateCastbarVisuals()
    end)

    castbarSpellNameCheck = CreateLabeledCheckButton(
        "MSUF_CastbarSpellNameCheck",
        "Show spell name",
        castbarEnemyGroup,
        16, -260
    )
    castbarSpellNameCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.castbarShowSpellName = self:GetChecked() and true or false
        MSUF_UpdateCastbarVisuals()
    end)
    --------------------------------------------------
    -- Grace-Periode für Castbars (Slider)
    --------------------------------------------------
    castbarGracePeriodSlider = CreateLabeledSlider(
        "MSUF_CastbarGracePeriodSlider",
        "Grace period (ms)",
        castbarEnemyGroup,
        0, 400, 10,       -- 0–400 ms, Schrittweite 10 ms
        175, -200          -- Neben den drei Toggles
    )
    castbarGracePeriodSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarGraceMs = math.floor(value + 0.5)
    end

    -- Kleine Warnung für High-Ping-User
    castbarGraceWarning = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    castbarGraceWarning:SetPoint("TOPLEFT", castbarGracePeriodSlider, "BOTTOMLEFT", -30, -35)
    castbarGraceWarning:SetWidth(200)
    castbarGraceWarning:SetJustifyH("LEFT")
    castbarGraceWarning:SetText("To high or low settings can brick the castbar")

    -- Icon-Position (rechte Spalte)
    castbarIconOffsetXSlider = CreateLabeledSlider(
        "MSUF_CastbarIconOffsetXSlider",
        "Icon X offset",
        castbarEnemyGroup,
        -300, 300, 1,
        360, -200
    )
    castbarIconOffsetXSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarIconOffsetX = value
        MSUF_UpdateCastbarVisuals()
    end

    castbarIconOffsetYSlider = CreateLabeledSlider(
        "MSUF_CastbarIconOffsetYSlider",
        "Icon Y offset",
        castbarEnemyGroup,
        -300, 300, 1,
        360, -270
    )
    castbarIconOffsetYSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarIconOffsetY = value
        MSUF_UpdateCastbarVisuals()
    end

    -- Offsets for Blizzard castbars relative to MSUF frames

    -- Target castbar offsets
    castbarTargetOffsetXSlider = CreateLabeledSlider(
        "MSUF_CastbarTargetOffsetXSlider",
        "Target castbar X offset",
        castbarTargetGroup,
        -500, 500, 1,
        0, -260
    )
    castbarTargetOffsetXSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarTargetOffsetX = value
        -- Reattach Blizzard target frame so the spell bar moves with the offsets
        MSUF_AttachBlizzardTargetFrame()
        MSUF_ReanchorTargetCastBar()
    end

    castbarTargetOffsetYSlider = CreateLabeledSlider(
        "MSUF_CastbarTargetOffsetYSlider",
        "Target castbar Y offset",
        castbarTargetGroup,
        -500, 500, 1,
        0, -320
    )
    castbarTargetOffsetYSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarTargetOffsetY = value
        MSUF_AttachBlizzardTargetFrame()
        MSUF_ReanchorTargetCastBar()
    end

    -- Focus castbar offsets


    -- Target castbar size (only this bar, overrides global width/height)
    castbarTargetBarWidthSlider = CreateLabeledSlider(
        "MSUF_CastbarTargetBarWidthSlider",
        "Target castbar width",
        castbarTargetGroup,
        50, 600, 1,
        0, -380
    )
    castbarTargetBarWidthSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarTargetBarWidth = math.floor(value + 0.5)

        -- Live-Bars (inkl. Preview) updaten
        MSUF_UpdateCastbarVisuals()
    end

    castbarTargetBarHeightSlider = CreateLabeledSlider(
        "MSUF_CastbarTargetBarHeightSlider",
        "Target castbar height",
        castbarTargetGroup,
        8, 40, 1,
        0, -440
    )
    castbarTargetBarHeightSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarTargetBarHeight = math.floor(value + 0.5)

        -- Live-Bars (inkl. Preview) updaten
        MSUF_UpdateCastbarVisuals()
    end

    -- Initialize target castbar size sliders with current values
    do
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        g = MSUF_DB.general

        baseWidth = g.castbarGlobalWidth  or 250
        baseHeight = g.castbarGlobalHeight or 18

        castbarTargetBarWidthSlider:SetValue(g.castbarTargetBarWidth  or baseWidth)
        castbarTargetBarHeightSlider:SetValue(g.castbarTargetBarHeight or baseHeight)
    end

    castbarFocusOffsetXSlider = CreateLabeledSlider(
        "MSUF_CastbarFocusOffsetXSlider",
        "Focus castbar X offset",
        castbarFocusGroup,
        -500, 500, 1,
        0, -260
    )
    castbarFocusOffsetXSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarFocusOffsetX = value
        MSUF_ReanchorFocusCastBar()
    end

    castbarFocusOffsetYSlider = CreateLabeledSlider(
        "MSUF_CastbarFocusOffsetYSlider",
        "Focus castbar Y offset",
        castbarFocusGroup,
        -500, 500, 1,
        0, -320
    )
    castbarFocusOffsetYSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarFocusOffsetY = value
        MSUF_ReanchorFocusCastBar()
    end

    ---------------------------------------

    -- Focus castbar size (only this bar, overrides global width/height)
    castbarFocusBarWidthSlider = CreateLabeledSlider(
        "MSUF_CastbarFocusBarWidthSlider",
        "Focus castbar width",
        castbarFocusGroup,
        50, 600, 1,
        0, -380
    )
    castbarFocusBarWidthSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarFocusBarWidth = math.floor(value + 0.5)

        -- Live-Bars + Previews anpassen
        MSUF_UpdateCastbarVisuals()
    end

    castbarFocusBarHeightSlider = CreateLabeledSlider(
        "MSUF_CastbarFocusBarHeightSlider",
        "Focus castbar height",
        castbarFocusGroup,
        8, 40, 1,
        0, -440
    )
    castbarFocusBarHeightSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarFocusBarHeight = math.floor(value + 0.5)

        -- Live-Bars + Previews anpassen
        MSUF_UpdateCastbarVisuals()
    end

    -- Initialize focus castbar size sliders with current values
    do
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        g = MSUF_DB.general

        baseWidth = g.castbarGlobalWidth  or 250
        baseHeight = g.castbarGlobalHeight or 18

        castbarFocusBarWidthSlider:SetValue(g.castbarFocusBarWidth  or baseWidth)
        castbarFocusBarHeightSlider:SetValue(g.castbarFocusBarHeight or baseHeight)
    end

-----------
    -- Castbar color dropdowns (interruptible / non-interruptible)
    ----------------------------------------------------------------------------------------------------
-- Castbar texture (SharedMedia)
--------------------------------------------------
local castbarTextureDrop

if LSM then
    castbarTextureLabel = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarTextureLabel:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 90)
    castbarTextureLabel:SetText("Castbar texture (SharedMedia)")

    castbarTextureDrop = CreateFrame("Frame", "MSUF_CastbarTextureDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate")
    castbarTextureDrop:SetPoint("TOPLEFT", castbarTextureLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(castbarTextureDrop, 180)

    -- Small statusbar preview for the currently selected castbar texture
    castbarTexturePreview = CreateFrame("StatusBar", nil, castbarEnemyGroup)
    castbarTexturePreview:SetSize(180, 10)
    castbarTexturePreview:SetPoint("TOPLEFT", castbarTextureDrop, "BOTTOMLEFT", 20, -6)
    castbarTexturePreview:SetMinMaxValues(0, 1)
    castbarTexturePreview:SetValue(1)

    local function CastbarTexturePreview_Update(texName)
        local texPath

        if LSM and texName and texName ~= "" then
            local ok, tex = pcall(LSM.Fetch, LSM, "statusbar", texName)
            if ok and tex then
                texPath = tex
            end
        end

        if not texPath and MSUF_GetCastbarTexture then
            texPath = MSUF_GetCastbarTexture()
        end

        if not texPath then
            texPath = "Interface\\TARGETINGFRAME\\UI-StatusBar"
        end

        castbarTexturePreview:SetStatusBarTexture(texPath)
    end

    local function CastbarTextureDropdown_Initialize(self, level)
        EnsureDB()
        info = UIDropDownMenu_CreateInfo()
        current = MSUF_DB.general.castbarTexture

        if LSM then
            list = LSM:List("statusbar") or {}
            table.sort(list, function(a, b) return a:lower() < b:lower() end)

            for _, name in ipairs(list) do
                info.text  = name
                info.value = name
               info.func  = function(btn)
    EnsureDB()
    MSUF_DB.general.castbarTexture = btn.value
    UIDropDownMenu_SetSelectedValue(castbarTextureDrop, btn.value)
    UIDropDownMenu_SetText(castbarTextureDrop, btn.value)

    -- sofort anwenden wie bei Bar-Textures
    if MSUF_UpdateCastbarTextures then
        MSUF_UpdateCastbarTextures()
    end
    if MSUF_UpdateCastbarVisuals then
        MSUF_UpdateCastbarVisuals()
    end

    if CastbarTexturePreview_Update then
        CastbarTexturePreview_Update(btn.value)
    end
end
                info.checked = (name == current)
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end

      UIDropDownMenu_Initialize(castbarTextureDrop, CastbarTextureDropdown_Initialize)

    EnsureDB()
    -- Wert aus der DB holen / Default setzen
    local texKey = MSUF_DB and MSUF_DB.general and MSUF_DB.general.castbarTexture

    if type(texKey) ~= "string" or texKey == "" then
        -- Gleicher Default wie bei den normalen Bars
        texKey = "Blizzard"
        MSUF_DB.general.castbarTexture = texKey
    end

    -- Dropdown korrekt befüllen (verhindert leeres Feld / "Custom")
    UIDropDownMenu_SetSelectedValue(castbarTextureDrop, texKey)
    UIDropDownMenu_SetText(castbarTextureDrop, texKey)

    -- Vorschau aktualisieren
    CastbarTexturePreview_Update(texKey)
else

    castbarTextureInfo = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    castbarTextureInfo:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 90)
    castbarTextureInfo:SetWidth(320)
    castbarTextureInfo:SetJustifyH("LEFT")
    castbarTextureInfo:SetText("Install the addon 'SharedMedia' (LibSharedMedia-3.0) to select castbar textures. Without it, the default UI castbar texture is used.")
end


    interruptibleColorLabel = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    interruptibleColorLabel:SetPoint("BOTTOMRIGHT", castbarEnemyGroup, "BOTTOMRIGHT", -100, 150)
    interruptibleColorLabel:SetText("Interruptible cast color")

    interruptibleColorDrop = CreateFrame("Frame", "MSUF_CastbarInterruptibleColorDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate")
   interruptibleColorDrop:SetPoint("TOPRIGHT", interruptibleColorLabel, "BOTTOMRIGHT", 0, -4)
    UIDropDownMenu_SetWidth(interruptibleColorDrop, 180)

    local function InterruptibleColorDropdown_Initialize(self, level)
        info = UIDropDownMenu_CreateInfo()
        EnsureDB()
        g = MSUF_DB.general or {}
        for _, c in ipairs(MSUF_COLOR_LIST) do
            info.text = c.label
            info.value = c.key
            info.func = function()
                EnsureDB()
                MSUF_DB.general.castbarInterruptibleColor = c.key
                UIDropDownMenu_SetSelectedValue(interruptibleColorDrop, c.key)
                if MSUF_UpdateCastbarVisuals then
                    MSUF_UpdateCastbarVisuals()
                end
            end
            info.checked = (g.castbarInterruptibleColor == c.key)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(interruptibleColorDrop, InterruptibleColorDropdown_Initialize)

    EnsureDB()
    if MSUF_DB and MSUF_DB.general then
        UIDropDownMenu_SetSelectedValue(interruptibleColorDrop, MSUF_DB.general.castbarInterruptibleColor or "turquoise")
    end

    nonInterruptibleColorLabel = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    nonInterruptibleColorLabel:SetPoint("TOPRIGHT", interruptibleColorLabel, "BOTTOMRIGHT", 0, -40)
    nonInterruptibleColorLabel:SetText("Non-interruptible cast color")

    nonInterruptibleColorDrop = CreateFrame("Frame", "MSUF_CastbarNonInterruptibleColorDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate")
   nonInterruptibleColorDrop:SetPoint("TOPRIGHT", nonInterruptibleColorLabel, "BOTTOMRIGHT", 0, -4)
    UIDropDownMenu_SetWidth(nonInterruptibleColorDrop, 180)

    local function NonInterruptibleColorDropdown_Initialize(self, level)
        info = UIDropDownMenu_CreateInfo()
        EnsureDB()
        g = MSUF_DB.general or {}
        for _, c in ipairs(MSUF_COLOR_LIST) do
            info.text = c.label
            info.value = c.key
            info.func = function()
                EnsureDB()
                MSUF_DB.general.castbarNonInterruptibleColor = c.key
                UIDropDownMenu_SetSelectedValue(nonInterruptibleColorDrop, c.key)
                if MSUF_UpdateCastbarVisuals then
                    MSUF_UpdateCastbarVisuals()
                end
            end
            info.checked = (g.castbarNonInterruptibleColor == c.key)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(nonInterruptibleColorDrop, NonInterruptibleColorDropdown_Initialize)

    EnsureDB()
    if MSUF_DB and MSUF_DB.general then
        UIDropDownMenu_SetSelectedValue(nonInterruptibleColorDrop, MSUF_DB.general.castbarNonInterruptibleColor or "red")
    end
    --------------------------------------------------
    -- Interrupt-Farbe (wird für "Interrupted"-Feedback benutzt)
    --------------------------------------------------
    interruptFeedbackColorLabel = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    -- Rechts unterhalb von "Non-interruptible cast color"
    interruptFeedbackColorLabel:SetPoint("TOPRIGHT", nonInterruptibleColorLabel, "BOTTOMRIGHT", 0, -40)
    interruptFeedbackColorLabel:SetText("Interrupt color (all castbars)")

    interruptFeedbackColorDrop = CreateFrame(
        "Frame",
        "MSUF_CastbarInterruptFeedbackColorDropdown",
        castbarEnemyGroup,
        "UIDropDownMenuTemplate"
    )
   interruptFeedbackColorDrop:SetPoint("TOPRIGHT", interruptFeedbackColorLabel, "BOTTOMRIGHT", 0, -4)
    UIDropDownMenu_SetWidth(interruptFeedbackColorDrop, 180)

    local function InterruptFeedbackColorDropdown_Initialize(self, level)
        info = UIDropDownMenu_CreateInfo()
        EnsureDB()
        g = MSUF_DB.general or {}
        for _, c in ipairs(MSUF_COLOR_LIST) do
            info.text  = c.label
            info.value = c.key
            info.func  = function()
                EnsureDB()
                MSUF_DB.general.castbarInterruptColor = c.key
                UIDropDownMenu_SetSelectedValue(interruptFeedbackColorDrop, c.key)
                if MSUF_UpdateCastbarVisuals then
                    MSUF_UpdateCastbarVisuals()
                end
                if MSUF_PositionPlayerCastbarPreview then
                    MSUF_PositionPlayerCastbarPreview()
                end
            end
            info.checked = (g.castbarInterruptColor == c.key)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(interruptFeedbackColorDrop, InterruptFeedbackColorDropdown_Initialize)

    EnsureDB()
    if MSUF_DB and MSUF_DB.general then
        UIDropDownMenu_SetSelectedValue(
            interruptFeedbackColorDrop,
            MSUF_DB.general.castbarInterruptColor or "red"
        )
    end
    --------------------------------------------------
    -- Texture & Color section (mittlere Trennlinie)
    --------------------------------------------------
    castbarTexColorTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    -- Position in der Mitte, etwas über "Castbar fill direction"
    castbarTexColorTitle:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 250)
    castbarTexColorTitle:SetText("Texture and Color")

    castbarTexColorLine = castbarEnemyGroup:CreateTexture(nil, "ARTWORK")
    castbarTexColorLine:SetColorTexture(1, 1, 1, 0.15)  -- gleiche Farbe wie "General"
    castbarTexColorLine:SetHeight(1)
    castbarTexColorLine:SetPoint("TOPLEFT", castbarTexColorTitle, "BOTTOMLEFT", 0, -4)
    castbarTexColorLine:SetPoint("RIGHT", castbarEnemyGroup, "RIGHT", -16, 0)

    --------------------------------------------------
    -- Castbar fill direction
    --------------------------------------------------
    castbarFillDirLabel = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarFillDirLabel:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 160)
    castbarFillDirLabel:SetText("Castbar fill direction")

    castbarFillDirDrop = CreateFrame("Frame", "MSUF_CastbarFillDirectionDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate")
    castbarFillDirDrop:SetPoint("TOPLEFT", castbarFillDirLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(castbarFillDirDrop, 180)

    local function CastbarFillDirDropdown_Initialize(self, level)
        info = UIDropDownMenu_CreateInfo()
        EnsureDB()
        g = MSUF_DB.general or {}
        current = g.castbarFillDirection or "RTL"

        items = {
            { key = "RTL", text = "Right to left (default)" },
            { key = "LTR", text = "Left to right" },
        }

        for _, item in ipairs(items) do
            info.text = item.text
            info.value = item.key
            info.func = function()
                EnsureDB()
                MSUF_DB.general.castbarFillDirection = item.key
                UIDropDownMenu_SetSelectedValue(castbarFillDirDrop, item.key)
            end
            info.checked = (current == item.key)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(castbarFillDirDrop, CastbarFillDirDropdown_Initialize)

    EnsureDB()
    if MSUF_DB and MSUF_DB.general then
        dir = MSUF_DB.general.castbarFillDirection or "RTL"
        UIDropDownMenu_SetSelectedValue(castbarFillDirDrop, dir)
    end

    --------------------------------------------------
    -- Player-Castbar-Subseite
    --------------------------------------------------
    castbarPlayerTitle = castbarPlayerGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    castbarPlayerTitle:SetPoint("TOPLEFT", castbarPlayerGroup, "TOPLEFT", 0, -180)
    castbarPlayerTitle:SetText("")

    -- Enable / disable player castbar
    castbarPlayerEnableCheck = CreateLabeledCheckButton(
        "MSUF_CastbarPlayerEnableCheck",
        "Enable player castbar",
        castbarPlayerGroup,
        0, -180
    )
    castbarPlayerEnableCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.enablePlayerCastbar = self:GetChecked() and true or false
        MSUF_ReanchorPlayerCastBar()
        if MSUF_PositionPlayerCastbarPreview then
            MSUF_PositionPlayerCastbarPreview()
        end
    end)

    -- Detach from player frame → use global anchor instead
    -- Player castbar offsets
    castbarPlayerOffsetXSlider = CreateLabeledSlider(
        "MSUF_CastbarPlayerOffsetXSlider",
        "Player castbar X offset",
        castbarPlayerGroup,
    -500, 500, 1,
    0, -260     
)
    castbarPlayerOffsetXSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarPlayerOffsetX = value
        MSUF_ReanchorPlayerCastBar()
    end

    castbarPlayerOffsetYSlider = CreateLabeledSlider(
        "MSUF_CastbarPlayerOffsetYSlider",
        "Player castbar Y offset",
        castbarPlayerGroup,
        -500, 500, 1,
        0, -320
    )
    castbarPlayerOffsetYSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarPlayerOffsetY = value
        MSUF_ReanchorPlayerCastBar()
    end
    -- Player cast time text offsets (rechte Seite)
    castbarPlayerTimeOffsetXSlider = CreateLabeledSlider(
        "MSUF_CastbarPlayerTimeOffsetXSlider",
        "Cast time X offset",
        castbarPlayerGroup,
        -500, 500, 1,
        220, -260     
    )
    castbarPlayerTimeOffsetXSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarPlayerTimeOffsetX = value
        MSUF_ReanchorPlayerCastBar()
    end

    castbarPlayerTimeOffsetYSlider = CreateLabeledSlider(
        "MSUF_CastbarPlayerTimeOffsetYSlider",
        "Cast time Y offset",
        castbarPlayerGroup,
        -500, 500, 1,
        220, -320    
    )
    castbarPlayerTimeOffsetYSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarPlayerTimeOffsetY = value
        MSUF_ReanchorPlayerCastBar()
    end

    -- Player castbar size (only this bar, overrides global width/height)
    castbarPlayerBarWidthSlider = CreateLabeledSlider(
        "MSUF_CastbarPlayerBarWidthSlider",
        "Player castbar width",
        castbarPlayerGroup,
        50, 600, 1,
        0, -380
    )
    castbarPlayerBarWidthSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarPlayerBarWidth = math.floor(value + 0.5)
        MSUF_UpdateCastbarVisuals()
        if MSUF_PositionPlayerCastbarPreview then
            MSUF_PositionPlayerCastbarPreview()
        end
    end
    -- Referenzen auf dem Panel speichern, damit LoadFromDB sie ohne neue Upvalues benutzen kann
    panel.castbarPlayerTimeOffsetXSlider = castbarPlayerTimeOffsetXSlider
    panel.castbarPlayerTimeOffsetYSlider = castbarPlayerTimeOffsetYSlider

    castbarPlayerBarHeightSlider = CreateLabeledSlider(
        "MSUF_CastbarPlayerBarHeightSlider",
        "Player castbar height",
        castbarPlayerGroup,
        8, 40, 1,
        0, -440
    )
    castbarPlayerBarHeightSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarPlayerBarHeight = math.floor(value + 0.5)
        MSUF_UpdateCastbarVisuals()
        if MSUF_PositionPlayerCastbarPreview then
            MSUF_PositionPlayerCastbarPreview()
        end
    end

    -- Initialize player castbar size sliders with current values
    do
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        g = MSUF_DB.general

        -- Fallback: globale Castbargröße oder Standard
        baseWidth = g.castbarGlobalWidth  or 250
        baseHeight = g.castbarGlobalHeight or 18

        castbarPlayerBarWidthSlider:SetValue(g.castbarPlayerBarWidth  or baseWidth)
        castbarPlayerBarHeightSlider:SetValue(g.castbarPlayerBarHeight or baseHeight)
    end


--------------------------------------------------
-- Auras (Basic)
--------------------------------------------------
auraTitle = auraGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
auraTitle:SetPoint("TOPLEFT", auraGroup, "TOPLEFT", 16, -120)
auraTitle:SetText("Auras (Basic)")

-- Dünne Trennlinie unter dem Haupttitel (wie im Player-Menü)
auraMainLine = auraGroup:CreateTexture(nil, "ARTWORK")
auraMainLine:SetColorTexture(1, 1, 1, 0.14)
auraMainLine:SetPoint("TOPLEFT", auraTitle, "BOTTOMLEFT", 0, -8)
auraMainLine:SetSize(560, 1)

-- MSWA Button rechts daneben
auraMSWAButton = CreateFrame("Button", "MSUF_AuraOpenMSWAButton", auraGroup, "UIPanelButtonTemplate")
auraMSWAButton:SetSize(260, 22)  -- breiter, damit der ganze Text reinpasst
auraMSWAButton:SetPoint("LEFT", auraTitle, "RIGHT", 8, 0)
auraMSWAButton:SetText("Open Midnight Simple Auras")

-- error text
auraMSWAError = auraGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
auraMSWAError:SetPoint("BOTTOMLEFT", auraGroup, "BOTTOMLEFT", 16, 16)
auraMSWAError:SetTextColor(1, 0.25, 0.25, 1)
auraMSWAError:SetText("")
auraMSWAError:Hide()

auraMSWAButton:SetScript("OnClick", function()
    auraMSWAError:Hide()

    -- a) HIER: Abfrage genau so
   mswaloaded = false
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        mswaloaded = C_AddOns.IsAddOnLoaded("MidnightSimpleAuras") and true or false
    elseif IsAddOnLoaded then
        mswaloaded = IsAddOnLoaded("MidnightSimpleAuras")
    end

    if not mswaloaded then
        auraMSWAError:SetText("Required addon 'MidnightSimpleAuras' is not loaded.")
        auraMSWAError:Show()
        return
    end

    -- b) Optionsfenster öffnen
    local opened = false

    if type(MidnightSimpleAuras_OpenOptions) == "function" then
        MidnightSimpleAuras_OpenOptions()
        opened = true
    elseif type(MSWA_OpenOptions) == "function" then
        MSWA_OpenOptions()
        opened = true
    elseif type(MSWA_ToggleOptions) == "function" then
        MSWA_ToggleOptions()
        opened = true
    end

    if not opened then
        auraMSWAError:SetText("Could not open MidnightSimpleAuras options.\nPlease update MidnightSimpleAuras to the latest version.")
        auraMSWAError:Show()
    end
end)

auraDisplayLabel = auraGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraDisplayLabel:SetPoint("TOPLEFT", auraMainLine, "BOTTOMLEFT", 0, -16)

    auraDisplayDrop = CreateFrame("Frame", "MSUF_TargetAuraDisplayDropdown", auraGroup, "UIDropDownMenuTemplate")
    auraDisplayDrop:SetPoint("TOPLEFT", auraDisplayLabel, "BOTTOMLEFT", -16, -4)

    auraDisplayOptions = {
        { key = "BUFFS_ONLY",        label = "Buffs ON, Debuffs OFF" },
        { key = "DEBUFFS_ONLY",      label = "Buffs OFF, Debuffs ON" },
        { key = "BUFFS_AND_DEBUFFS", label = "Buffs ON, Debuffs ON" },
        { key = "NONE",              label = "All buffs & debuffs OFF" },
    }

    local function AuraDisplayDropdown_Initialize(self, level)
        EnsureDB()
        g = MSUF_DB.general or {}
        current = g.targetAuraDisplay or "BUFFS_AND_DEBUFFS"

        info = UIDropDownMenu_CreateInfo()
        for _, opt in ipairs(auraDisplayOptions) do
            info.text    = opt.label
            info.value   = opt.key
            info.checked = (current == opt.key)
            info.func    = function(button)
                EnsureDB()
                MSUF_DB.general.targetAuraDisplay = button.value or "BUFFS_AND_DEBUFFS"
                UIDropDownMenu_SetSelectedValue(auraDisplayDrop, MSUF_DB.general.targetAuraDisplay)

                if UnitFrames and UnitFrames["target"] then
                    MSUF_UpdateTargetAuras(UnitFrames["target"])
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(auraDisplayDrop, AuraDisplayDropdown_Initialize)
    UIDropDownMenu_SetWidth(auraDisplayDrop, 220)

    C_Timer.After(0.1, function()
        EnsureDB()
        if MSUF_TargetAuraDisplayDropdown then
            UIDropDownMenu_SetSelectedValue(
                MSUF_TargetAuraDisplayDropdown,
                MSUF_DB.general.targetAuraDisplay or "BUFFS_AND_DEBUFFS"
            )
        end
    end)


    --------------------------------------------------
    
    --------------------------------------------------
    -- Target aura bar position (width/height/scale/offset)
    --------------------------------------------------
    auraPosLabel = auraGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    auraPosLabel:SetPoint("TOPLEFT", auraDisplayDrop, "BOTTOMLEFT", 0, -32)
    auraPosLabel:SetText("Target aura bar position")

    -- Trennlinie unter der Überschrift (wie im Player-Menü)
    auraPosLine = auraGroup:CreateTexture(nil, "ARTWORK")
    auraPosLine:SetColorTexture(1, 1, 1, 0.14)
    auraPosLine:SetPoint("TOPLEFT", auraPosLabel, "BOTTOMLEFT", 0, -4)
    auraPosLine:SetSize(560, 1)

    -- Create sliders; we re-anchor them below the label to avoid overlaps
    targetAuraWidthSlider = CreateLabeledSlider(
        "MSUF_TargetAuraWidthSlider", "Aura bar width", auraGroup,
        0, 999, 1,
        16, -90
    )

    targetAuraHeightSlider = CreateLabeledSlider(
        "MSUF_TargetAuraHeightSlider", "Aura icon height", auraGroup,
        0, 200, 1,
        16, -140
    )

    targetAuraScaleSlider = CreateLabeledSlider(
        "MSUF_TargetAuraScaleSlider", "Aura icon scale", auraGroup,
        0.2, 2.0, 0.05,
        16, -210
    )

    targetAuraAlphaSlider = CreateLabeledSlider(
        "MSUF_TargetAuraAlphaSlider", "Aura opacity", auraGroup,
        0.1, 1.0, 0.05,
        16, -280
    )

    targetAuraXOffsetSlider = CreateLabeledSlider(
        "MSUF_TargetAuraXOffsetSlider", "Aura X offset", auraGroup,
        -999, 999, 1,
        16, -350
    )

    targetAuraYOffsetSlider = CreateLabeledSlider(
        "MSUF_TargetAuraYOffsetSlider", "Aura Y offset", auraGroup,
        -999, 999, 1,
        16, -420
    )

-- Arrange sliders relative to the header label so nothing overlaps
-- Width slider ist aktuell im Release ausgeblendet (Feature WIP)
targetAuraWidthSlider:ClearAllPoints()
targetAuraWidthSlider:SetPoint("TOPLEFT", auraPosLine, "BOTTOMLEFT", 0, -10)

-- Width-Slider + Editbox + +/- Buttons verstecken, aber im Code behalten
targetAuraWidthSlider:Hide()
if targetAuraWidthSlider.editBox then targetAuraWidthSlider.editBox:Hide() end
if targetAuraWidthSlider.minusButton then targetAuraWidthSlider.minusButton:Hide() end
if targetAuraWidthSlider.plusButton then targetAuraWidthSlider.plusButton:Hide() end

-- Aura icon height ist der erste sichtbare Slider unter der Linie
targetAuraHeightSlider:ClearAllPoints()
targetAuraHeightSlider:SetPoint("TOPLEFT", auraPosLine, "BOTTOMLEFT", 0, -10)

    targetAuraScaleSlider:ClearAllPoints()
    targetAuraScaleSlider:SetPoint("TOPLEFT", targetAuraHeightSlider, "BOTTOMLEFT", 0, -60)

    targetAuraAlphaSlider:ClearAllPoints()
    targetAuraAlphaSlider:SetPoint("TOPLEFT", targetAuraScaleSlider, "BOTTOMLEFT", 0, -60)

    targetAuraXOffsetSlider:ClearAllPoints()
    targetAuraXOffsetSlider:SetPoint("TOPLEFT", targetAuraAlphaSlider, "BOTTOMLEFT", 0, -60)

    targetAuraYOffsetSlider:ClearAllPoints()
    targetAuraYOffsetSlider:SetPoint("TOPLEFT", targetAuraXOffsetSlider, "BOTTOMLEFT", 0, -60)

    -- Slider callbacks: write into MSUF_DB.general and refresh target auras
    targetAuraWidthSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.targetAuraWidth = math.floor(value + 0.5)
        if UnitFrames and UnitFrames["target"] then
            MSUF_UpdateTargetAuras(UnitFrames["target"])
        end
    end

    targetAuraHeightSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.targetAuraHeight = math.floor(value + 0.5)
        if UnitFrames and UnitFrames["target"] then
            MSUF_UpdateTargetAuras(UnitFrames["target"])
        end
    end

    targetAuraScaleSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.targetAuraScale = value
        if UnitFrames and UnitFrames["target"] then
            MSUF_UpdateTargetAuras(UnitFrames["target"])
        end
    end

    targetAuraAlphaSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.targetAuraAlpha = value
        if UnitFrames and UnitFrames["target"] then
            MSUF_UpdateTargetAuras(UnitFrames["target"])
        end
    end

    targetAuraXOffsetSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.targetAuraOffsetX = math.floor(value + 0.1)
        if UnitFrames and UnitFrames["target"] then
            MSUF_UpdateTargetAuras(UnitFrames["target"])
        end
    end

    targetAuraYOffsetSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.targetAuraOffsetY = math.floor(value + 0.1)
        if UnitFrames and UnitFrames["target"] then
            MSUF_UpdateTargetAuras(UnitFrames["target"])
        end
    end

-- BARS TAB (Gradient + Dark-Mode-Farben)
    --------------------------------------------------
    BAR_DROPDOWN_WIDTH = 180
    barsTitle = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    barsTitle:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 16, -120)
    barsTitle:SetText("Bar appearance")

    -- Bar mode selection (dropdown instead of two checkboxes)
    barModeLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    barModeLabel:SetPoint("TOPLEFT", barsTitle, "BOTTOMLEFT", 0, -8)
    barModeLabel:SetText("Bar mode")

    barModeDrop = CreateFrame("Frame", "MSUF_BarModeDropdown", barGroup, "UIDropDownMenuTemplate")
    barModeDrop:SetPoint("TOPLEFT", barModeLabel, "BOTTOMLEFT", -16, -4)

    barModeOptions = {
        { key = "dark",  label = "Dark Mode (dark black bars)" },
        { key = "class", label = "Class Color Mode (color HP bars)" },
    }

local function BarModeDropdown_Initialize(self, level)
    EnsureDB()
    info = UIDropDownMenu_CreateInfo()
    local current = MSUF_DB.general.barMode or "dark"

    for _, opt in ipairs(barModeOptions) do
        -- eigene Upvalues pro Eintrag
        local thisKey   = opt.key
        local thisLabel = opt.label

        info.text  = thisLabel
        info.value = thisKey
        info.func  = function(btn)
            EnsureDB()
            local mode = (btn and btn.value) or thisKey
            MSUF_DB.general.barMode = mode

            if mode == "dark" then
                MSUF_DB.general.darkMode       = true
                MSUF_DB.general.useClassColors = false
            elseif mode == "class" then
                MSUF_DB.general.darkMode       = false
                MSUF_DB.general.useClassColors = true
            end

            UIDropDownMenu_SetSelectedValue(barModeDrop, mode)
            UIDropDownMenu_SetText(barModeDrop, thisLabel)
            ApplyAllSettings()
        end

        info.checked = (thisKey == current)
        UIDropDownMenu_AddButton(info, level)
    end
end

UIDropDownMenu_Initialize(barModeDrop, BarModeDropdown_Initialize)
UIDropDownMenu_SetWidth(barModeDrop, BAR_DROPDOWN_WIDTH)

    local function MSUF_UpdateBarModeDropdown()
        if not barModeDrop then return end
        EnsureDB()
        current = MSUF_DB.general.barMode or "dark"
        label = "Dark Mode (dark black bars)"
        if current == "class" then
            label = "Class Color Mode (color HP bars)"
        end
        UIDropDownMenu_SetSelectedValue(barModeDrop, current)
        UIDropDownMenu_SetText(barModeDrop, label)
    end

    -- Gradient toggle directly below bar mode selection
    gradientCheck = CreateLabeledCheckButton(
        "MSUF_GradientEnableCheck",
        "Enable HP bar gradient",
        barGroup,
        16, -260
    )

    -- Gradient-Stärke (0–100, wir skalieren später auf 0–1)
    gradientSlider = CreateLabeledSlider(
        "MSUF_GradientStrengthSlider",
        "Gradient intensity",
        barGroup,
        0, 100, 5,
        16, -300
    )
    -- Toggle: small power bar under target HP bar
    targetPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_TargetPowerBarCheck",
        "Show power bar on target frame",
        barGroup,
        260, -260
    )

    -- Toggle: power bar on boss frames
    bossPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_BossPowerBarCheck",
        "Show power bar on boss frames",
        barGroup,
        260, -290
    )

    -- Toggle: power bar under player HP bar
    playerPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_PlayerPowerBarCheck",
        "Show power bar on player frames",
        barGroup,
        260, -320
    )

    -- Toggle: power bar under focus HP bar
    focusPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_FocusPowerBarCheck",
        "Show power bar on focus",
        barGroup,
        260, -350
    )

    powerBarHeightLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerBarHeightLabel:SetPoint("TOPLEFT", focusPowerBarCheck, "BOTTOMLEFT", 0, -4)
    powerBarHeightLabel:SetText("Power bar height")

    powerBarHeightEdit = CreateFrame("EditBox", "MSUF_PowerBarHeightEdit", barGroup, "InputBoxTemplate")
    powerBarHeightEdit:SetSize(40, 20)
    powerBarHeightEdit:SetAutoFocus(false)
    powerBarHeightEdit:SetPoint("LEFT", powerBarHeightLabel, "RIGHT", 4, 0)
    powerBarHeightEdit:SetTextInsets(4, 4, 2, 2)

    -- HP text display mode dropdown
    hpModeLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hpModeLabel:SetPoint("TOPLEFT", powerBarHeightLabel, "BOTTOMLEFT", 0, -16)
    hpModeLabel:SetText("HP text mode")

    hpModeDrop = CreateFrame("Frame", "MSUF_HPTextModeDropdown", barGroup, "UIDropDownMenuTemplate")
    hpModeDrop:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", -16, -4)

    hpModeOptions = {
        { key = "FULL_ONLY",          label = "Full value only" },
        { key = "FULL_PLUS_PERCENT",  label = "Full value + %" },
        { key = "PERCENT_ONLY",       label = "Only %" },
    }

    local function HPModeDropdown_Initialize(self, level)
        info = UIDropDownMenu_CreateInfo()
        EnsureDB()
        current = MSUF_DB.general.hpTextMode or "FULL_PLUS_PERCENT"

        for _, opt in ipairs(hpModeOptions) do
            info.text  = opt.label
            info.value = opt.key
            info.func  = function(btn)
                EnsureDB()
                MSUF_DB.general.hpTextMode = btn.value

                UIDropDownMenu_SetSelectedValue(hpModeDrop, btn.value)
                UIDropDownMenu_SetText(hpModeDrop, opt.label)

                -- Alles neu zeichnen, damit der neue Modus sofort sichtbar wird
                ApplyAllSettings()
            end
            info.checked = (opt.key == current)
            UIDropDownMenu_AddButton(info, level)
        end
    end

UIDropDownMenu_Initialize(hpModeDrop, HPModeDropdown_Initialize)
UIDropDownMenu_SetWidth(hpModeDrop, BAR_DROPDOWN_WIDTH)

    do
        EnsureDB()
        current = MSUF_DB.general.hpTextMode or "FULL_PLUS_PERCENT"
        labelText = "Full value + %"
        for _, opt in ipairs(hpModeOptions) do
            if opt.key == current then
                labelText = opt.label
                break
            end
        end
        UIDropDownMenu_SetSelectedValue(hpModeDrop, current)
        UIDropDownMenu_SetText(hpModeDrop, labelText)
    end




    -- Dark-Mode-Bar-Farbe
    darkToneLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    darkToneLabel:SetPoint("TOPLEFT", barModeDrop, "BOTTOMLEFT", 16, -12)
    darkToneLabel:SetText("Dark mode bar color")

    darkToneDrop = CreateFrame("Frame", "MSUF_DarkToneDropdown", barGroup, "UIDropDownMenuTemplate")
    darkToneDrop:SetPoint("TOPLEFT", darkToneLabel, "BOTTOMLEFT", -16, -4)

    darkToneChoices = {
        { key = "black",    label = "Pure black" },
        { key = "darkgray", label = "Dark gray" },
        { key = "softgray", label = "Soft gray" },
    }

    local function DarkToneDropdown_Initialize(self, level)
        EnsureDB()
        info = UIDropDownMenu_CreateInfo()
        current = MSUF_DB.general.darkBarTone or "black"

        for _, opt in ipairs(darkToneChoices) do
            info.text  = opt.label
            info.value = opt.key
            info.func  = function()
                EnsureDB()
                MSUF_DB.general.darkBarTone = opt.key
                UIDropDownMenu_SetSelectedValue(darkToneDrop, opt.key)
                ApplyAllSettings()
            end
            info.checked = (opt.key == current)
            UIDropDownMenu_AddButton(info)
        end
    end
UIDropDownMenu_Initialize(darkToneDrop, DarkToneDropdown_Initialize)
UIDropDownMenu_SetWidth(darkToneDrop, BAR_DROPDOWN_WIDTH)
UIDropDownMenu_Initialize(darkToneDrop, DarkToneDropdown_Initialize)
UIDropDownMenu_SetWidth(darkToneDrop, BAR_DROPDOWN_WIDTH)

    --------------------------------------------------
    -- NEU: Brightness-Slider für Dark-Mode-Hintergrund
    --------------------------------------------------
    darkBgBrightnessSlider = CreateLabeledSlider(
        "MSUF_DarkBgBrightnessSlider",
        "Background brightness",
        barGroup,
        1, 99, 1,   -- 10–40 -> 0.10–0.40
        260, -160    -- Startposition (wird gleich überschrieben)
    )

    -- Auf die Höhe von "Dark mode bar color" neben das Dropdown setzen
    darkBgBrightnessSlider:ClearAllPoints()
    darkBgBrightnessSlider:SetPoint("LEFT", darkToneDrop, "RIGHT", 40, 0)

    -- Wenn der Slider bewegt wird -> Wert in die DB schreiben
    darkBgBrightnessSlider.onValueChanged = function(self, value)
        EnsureDB()
        if not MSUF_DB.general then MSUF_DB.general = {} end

        -- value kommt als 10–40, wir speichern 0.10–0.40
        v = math.floor(value + 0.5)
        if v < 1 then v = 11 end
        if v > 99 then v = 99 end

        MSUF_DB.general.darkBgBrightness = v / 100
        ApplyAllSettings()
    end

    -- OPTIONAL: etwas breiter machen, damit es hübsch aussieht
    darkBgBrightnessSlider:SetWidth(180)

    -- OPTIONAL: Labels etwas sprechender machen
    _G["MSUF_DarkBgBrightnessSliderLow"]:SetText("1")
    _G["MSUF_DarkBgBrightnessSliderHigh"]:SetText("99")

    -- OPTIONAL: Editbox direkt mit Startwert befüllen
    if darkBgBrightnessSlider.editBox then
        darkBgBrightnessSlider.editBox:SetText("25")
    end

    -- OPTIONAL: Bar texture selection via SharedMedia
    local barTextureDrop

    if LSM then
        barTextureLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        barTextureLabel:SetPoint("TOPLEFT", darkToneLabel, "BOTTOMLEFT", 0, -75)
        barTextureLabel:SetText("Bar texture (SharedMedia)")

        barTextureDrop = CreateFrame("Frame", "MSUF_BarTextureDropdown", barGroup, "UIDropDownMenuTemplate")
        barTextureDrop:SetPoint("TOPLEFT", barTextureLabel, "BOTTOMLEFT", -16, -4)

        local function BarTextureDropdown_Initialize(self, level)
            EnsureDB()
            info = UIDropDownMenu_CreateInfo()
            current = MSUF_DB.general.barTexture or "Blizzard"

            if LSM then
                list = LSM:List("statusbar") or {}
                table.sort(list, function(a, b) return a:lower() < b:lower() end)

                for _, name in ipairs(list) do
                    info.text  = name
                    info.value = name
                    info.func  = function(btn)
                        EnsureDB()
                        MSUF_DB.general.barTexture = btn.value
                        UIDropDownMenu_SetSelectedValue(barTextureDrop, btn.value)
                        UIDropDownMenu_SetText(barTextureDrop, btn.value)
                        ApplyAllSettings()
                        UpdateAllBarTextures()
                    end
                    info.checked = (name == current)
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end

UIDropDownMenu_Initialize(barTextureDrop, BarTextureDropdown_Initialize)
UIDropDownMenu_SetWidth(barTextureDrop, BAR_DROPDOWN_WIDTH)

        local function MSUF_UpdateBarTextureDropdown()
            if not barTextureDrop then return end
            EnsureDB()
            current = MSUF_DB.general.barTexture or "Blizzard"
            UIDropDownMenu_SetSelectedValue(barTextureDrop, current)
            UIDropDownMenu_SetText(barTextureDrop, current)
        end
    else
        barTextureInfo = barGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        barTextureInfo:SetPoint("TOPLEFT", darkToneLabel, "BOTTOMLEFT", 0, -40)
        barTextureInfo:SetWidth(320)
        barTextureInfo:SetJustifyH("LEFT")
        barTextureInfo:SetText("Install the addon 'SharedMedia' (LibSharedMedia-3.0) to unlock additional bar textures.\nWithout it, the default Blizzard texture is used.")
        local function MSUF_UpdateBarTextureDropdown()
            -- nothing to sync if there is no dropdown
        end
    end
    --------------------------------------------------
    -- BAR BORDER OPTIONS
    --------------------------------------------------

    -- Toggle: Enable border
    borderCheck = CreateLabeledCheckButton(
        "MSUF_UseBarBorderCheck",
        "Show bar border",
        barGroup,
        16, -350
    )

    -- Dropdown: Border style
    borderStyleLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    borderStyleLabel:SetPoint("TOPLEFT", borderCheck, "BOTTOMLEFT", 4, -10)
    borderStyleLabel:SetText("Border style")

    borderDrop = CreateFrame("Frame", "MSUF_BorderStyleDropdown", barGroup, "UIDropDownMenuTemplate")
    borderDrop:SetPoint("TOPLEFT", borderStyleLabel, "BOTTOMLEFT", -16, -4)

    borderOptions = {
        { key = "THIN",   label = "Thin" },
        { key = "THICK",  label = "Thick" },
        { key = "SHADOW", label = "Shadow" },
        { key = "GLOW",   label = "Glow" },
    }

    local function BorderStyle_Initialize(self, level)
        EnsureDB()
        info = UIDropDownMenu_CreateInfo()
        current = MSUF_DB.general.barBorderStyle or "THIN"

        for _, opt in ipairs(borderOptions) do
            -- eigene Upvalues pro Eintrag
            local thisKey   = opt.key
            local thisLabel = opt.label

            info.text  = thisLabel
            info.value = thisKey
            info.func  = function()
                EnsureDB()
                MSUF_DB.general.barBorderStyle = thisKey
                UIDropDownMenu_SetSelectedValue(borderDrop, thisKey)
                UIDropDownMenu_SetText(borderDrop, thisLabel)
                ApplyAllSettings()
            end
            info.checked = (thisKey == current)
            UIDropDownMenu_AddButton(info, level)
        end
    end

UIDropDownMenu_Initialize(borderDrop, BorderStyle_Initialize)
UIDropDownMenu_SetWidth(borderDrop, BAR_DROPDOWN_WIDTH)




    -- Reaktionen auf User-Input
    gradientCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.enableGradient = self:GetChecked() and true or false
        ApplyAllSettings()
    end)

    gradientSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.gradientStrength = (value or 0) / 100
        ApplyAllSettings()
    end
    -- Toggle: Show bar border (Bars-Tab überschreibt globalen Wert)
    if borderCheck then
        borderCheck:SetScript("OnClick", function(self)
            EnsureDB()
            MSUF_DB.bars = MSUF_DB.bars or {}
            -- true/false erzwingen, nil = kein Override
            MSUF_DB.bars.showBarBorder = self:GetChecked() and true or false
            ApplyAllSettings()
        end)
    end
    if targetPowerBarCheck then
        targetPowerBarCheck:SetScript("OnClick", function(self)
            EnsureDB()
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.showTargetPowerBar = self:GetChecked() and true or false
            ApplyAllSettings()
        end)
    end

    if bossPowerBarCheck then
        bossPowerBarCheck:SetScript("OnClick", function(self)
            EnsureDB()
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.showBossPowerBar = self:GetChecked() and true or false
            ApplyAllSettings()
        end)
    end

    if playerPowerBarCheck then
        playerPowerBarCheck:SetScript("OnClick", function(self)
            EnsureDB()
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.showPlayerPowerBar = self:GetChecked() and true or false
            ApplyAllSettings()
        end)
    end

    if focusPowerBarCheck then
        focusPowerBarCheck:SetScript("OnClick", function(self)
            EnsureDB()
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.showFocusPowerBar = self:GetChecked() and true or false
            ApplyAllSettings()
        end)
    end

    if powerBarHeightEdit then
        powerBarHeightEdit:SetScript("OnEnterPressed", function(self)
            MSUF_UpdatePowerBarHeightFromEdit(self)
            self:ClearFocus()
        end)
        powerBarHeightEdit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        powerBarHeightEdit:SetScript("OnEditFocusLost", function(self)
            -- keep text but normalize silently
            MSUF_UpdatePowerBarHeightFromEdit(self)
        end)
    end

    --------------------------------------------------
    -- Store widget references on the panel
    -- (so LoadFromDB does not capture them as upvalues)
    --------------------------------------------------
    panel.anchorEdit                 = anchorEdit
    -- panel.anchorCheck removed (anchor toggle only in Edit Mode)

    panel.fontDrop                   = fontDrop
    panel.fontColorDrop              = fontColorDrop

    panel.nameFontSizeSlider         = nameFontSizeSlider
    panel.hpFontSizeSlider           = hpFontSizeSlider
    panel.powerFontSizeSlider        = powerFontSizeSlider
    panel.fontSizeSlider             = fontSizeSlider  -- falls vorhanden, sonst einfach nil

    panel.boldCheck                  = boldCheck
    panel.nameClassColorCheck        = nameClassColorCheck
    panel.npcNameRedCheck            = npcNameRedCheck
    panel.shortenNamesCheck          = shortenNamesCheck
    panel.textBackdropCheck          = textBackdropCheck

    panel.highlightEnableCheck       = highlightEnableCheck
    panel.highlightColorDrop         = highlightColorDrop

    panel.castbarTargetOffsetXSlider = castbarTargetOffsetXSlider
    panel.castbarTargetOffsetYSlider = castbarTargetOffsetYSlider
    panel.castbarFocusOffsetXSlider  = castbarFocusOffsetXSlider
    panel.castbarFocusOffsetYSlider  = castbarFocusOffsetYSlider
    panel.castbarPlayerOffsetXSlider = castbarPlayerOffsetXSlider
    panel.castbarPlayerOffsetYSlider = castbarPlayerOffsetYSlider

    panel.castbarTargetBarWidthSlider   = castbarTargetBarWidthSlider
    panel.castbarTargetBarHeightSlider  = castbarTargetBarHeightSlider
    panel.castbarFocusBarWidthSlider    = castbarFocusBarWidthSlider
    panel.castbarFocusBarHeightSlider   = castbarFocusBarHeightSlider
    panel.castbarPlayerBarWidthSlider   = castbarPlayerBarWidthSlider
    panel.castbarPlayerBarHeightSlider  = castbarPlayerBarHeightSlider

    panel.castbarTargetCheck         = castbarTargetCheck
    panel.castbarFocusCheck          = castbarFocusCheck
    panel.castbarPlayerEnableCheck   = castbarPlayerEnableCheck
    panel.castbarIconCheck           = castbarIconCheck
    panel.castbarSpellNameCheck      = castbarSpellNameCheck
    panel.castbarSpellNameFontSizeSlider = castbarSpellNameFontSizeSlider
    panel.castbarIconOffsetXSlider   = castbarIconOffsetXSlider
    panel.castbarIconOffsetYSlider   = castbarIconOffsetYSlider
 panel.castbarGracePeriodSlider   = castbarGracePeriodSlider

    panel.auraDisplayDrop            = auraDisplayDrop
    panel.targetAuraWidthSlider      = targetAuraWidthSlider
    panel.targetAuraHeightSlider     = targetAuraHeightSlider
    panel.targetAuraScaleSlider      = targetAuraScaleSlider
    panel.targetAuraAlphaSlider      = targetAuraAlphaSlider
    panel.targetAuraXOffsetSlider    = targetAuraXOffsetSlider
    panel.targetAuraYOffsetSlider    = targetAuraYOffsetSlider

    panel.gradientCheck              = gradientCheck
    panel.gradientSlider             = gradientSlider

    panel.targetPowerBarCheck        = targetPowerBarCheck
    panel.bossPowerBarCheck          = bossPowerBarCheck
    panel.playerPowerBarCheck        = playerPowerBarCheck
    panel.focusPowerBarCheck         = focusPowerBarCheck
    panel.powerBarHeightEdit         = powerBarHeightEdit

    panel.hpModeDrop                 = hpModeDrop
    panel.darkToneDrop               = darkToneDrop
    panel.darkBgBrightnessSlider     = darkBgBrightnessSlider
    panel.barTextureDrop             = barTextureDrop
    panel.borderCheck                = borderCheck
    panel.borderDrop                 = borderDrop

    panel.widthSlider                = widthSlider
    panel.heightSlider               = heightSlider
    panel.xSlider                    = xSlider
    panel.ySlider                    = ySlider
    panel.bossSpacingSlider          = bossSpacingSlider

    panel.showNameCB                 = showNameCB
    panel.showHPCB                   = showHPCB
    panel.showPowerCB                = showPowerCB
    panel.enableFrameCB              = enableFrameCB
    panel.bossTestCB                 = bossTestCB

--------------------------------------------------
-- Store widget references on the panel
-- (so LoadFromDB can use self.* instead of upvalues)
--------------------------------------------------
panel.frameWidthSlider   = frameWidthSlider
panel.frameHeightSlider  = frameHeightSlider
panel.frameScaleSlider   = frameScaleSlider
panel.showPowerCheck     = showPowerCheck

panel.fontSizeSlider     = fontSizeSlider
panel.updateThrottleSlider = updateThrottleSlider
panel.powerBarHeightSlider = powerBarHeightSlider
panel.infoTooltipDisableCheck = infoTooltipDisableCheck


       --------------------------------------------------
    -- DB → UI  (uses panel fields instead of upvalues)
    --------------------------------------------------
    function panel:LoadFromDB()
        EnsureDB()

        g = MSUF_DB.general or {}
        bars = MSUF_DB.bars    or {}

        -- Pull widget references from self instead of upvalues
        anchorEdit = self.anchorEdit
        anchorCheck = self.anchorCheck

        fontDrop = self.fontDrop
        fontColorDrop = self.fontColorDrop

        nameFontSizeSlider = self.nameFontSizeSlider
        hpFontSizeSlider = self.hpFontSizeSlider
        powerFontSizeSlider = self.powerFontSizeSlider
        fontSizeSlider = self.fontSizeSlider

        boldCheck = self.boldCheck
        nameClassColorCheck = self.nameClassColorCheck
        npcNameRedCheck = self.npcNameRedCheck
        shortenNamesCheck = self.shortenNamesCheck
        textBackdropCheck = self.textBackdropCheck

        highlightEnableCheck = self.highlightEnableCheck
        highlightColorDrop = self.highlightColorDrop

        castbarTargetOffsetXSlider = self.castbarTargetOffsetXSlider
        castbarTargetOffsetYSlider = self.castbarTargetOffsetYSlider
        castbarFocusOffsetXSlider = self.castbarFocusOffsetXSlider
        castbarFocusOffsetYSlider = self.castbarFocusOffsetYSlider
        castbarPlayerOffsetXSlider = self.castbarPlayerOffsetXSlider
        castbarPlayerOffsetYSlider = self.castbarPlayerOffsetYSlider

        castbarTargetBarWidthSlider = self.castbarTargetBarWidthSlider
        castbarTargetBarHeightSlider = self.castbarTargetBarHeightSlider
        castbarFocusBarWidthSlider = self.castbarFocusBarWidthSlider
        castbarFocusBarHeightSlider = self.castbarFocusBarHeightSlider
        castbarPlayerBarWidthSlider = self.castbarPlayerBarWidthSlider
        castbarPlayerBarHeightSlider = self.castbarPlayerBarHeightSlider

        castbarTargetCheck = self.castbarTargetCheck
        castbarFocusCheck = self.castbarFocusCheck
        castbarPlayerEnableCheck = self.castbarPlayerEnableCheck
        castbarIconCheck = self.castbarIconCheck
        castbarSpellNameCheck = self.castbarSpellNameCheck
        castbarSpellNameFontSizeSlider = self.castbarSpellNameFontSizeSlider
        castbarIconOffsetXSlider = self.castbarIconOffsetXSlider
        castbarIconOffsetYSlider = self.castbarIconOffsetYSlider

                castbarTargetCheck = self.castbarTargetCheck
        castbarFocusCheck = self.castbarFocusCheck
        castbarPlayerEnableCheck = self.castbarPlayerEnableCheck
        castbarIconCheck = self.castbarIconCheck
        castbarSpellNameCheck = self.castbarSpellNameCheck
        castbarSpellNameFontSizeSlider = self.castbarSpellNameFontSizeSlider
        castbarIconOffsetXSlider = self.castbarIconOffsetXSlider
        castbarIconOffsetYSlider = self.castbarIconOffsetYSlider
        castbarGracePeriodSlider = self.castbarGracePeriodSlider

        auraDisplayDrop = self.auraDisplayDrop
        targetAuraWidthSlider = self.targetAuraWidthSlider
        targetAuraHeightSlider = self.targetAuraHeightSlider
        targetAuraScaleSlider = self.targetAuraScaleSlider
        targetAuraAlphaSlider = self.targetAuraAlphaSlider
        targetAuraXOffsetSlider = self.targetAuraXOffsetSlider
        targetAuraYOffsetSlider = self.targetAuraYOffsetSlider

        gradientCheck = self.gradientCheck
        gradientSlider = self.gradientSlider

        targetPowerBarCheck = self.targetPowerBarCheck
        bossPowerBarCheck = self.bossPowerBarCheck
        playerPowerBarCheck = self.playerPowerBarCheck
        focusPowerBarCheck = self.focusPowerBarCheck
        powerBarHeightEdit = self.powerBarHeightEdit

        hpModeDrop = self.hpModeDrop
        darkToneDrop = self.darkToneDrop
        darkBgBrightnessSlider = self.darkBgBrightnessSlider
        borderCheck = self.borderCheck
        borderDrop = self.borderDrop

        widthSlider = self.widthSlider
        heightSlider = self.heightSlider
        xSlider = self.xSlider
        ySlider = self.ySlider
        bossSpacingSlider = self.bossSpacingSlider

        showNameCB = self.showNameCB
        showHPCB = self.showHPCB
        showPowerCB = self.showPowerCB
        enableFrameCB = self.enableFrameCB
        bossTestCB = self.bossTestCB

        nameOffsetXSlider = self.nameOffsetXSlider
        nameOffsetYSlider = self.nameOffsetYSlider
        hpOffsetXSlider = self.hpOffsetXSlider
        hpOffsetYSlider = self.hpOffsetYSlider
        powerOffsetXSlider = self.powerOffsetXSlider
        powerOffsetYSlider = self.powerOffsetYSlider

        --------------------------------------------------
        -- General (always sync)
        --------------------------------------------------
        if anchorEdit then
            anchorEdit:SetText(g.anchorName or "UIParent")
        end
        if anchorCheck then
            anchorCheck:SetChecked(g.anchorToCooldown and true or false)
        end

             -- Global font dropdown: Wert + sichtbaren Text korrekt setzen
        if fontDrop and g.fontKey then
            -- sicherstellen, dass die Font-Liste existiert
            if (not fontChoices or #fontChoices == 0) and MSUF_RebuildFontChoices then
                MSUF_RebuildFontChoices()
            end

            UIDropDownMenu_SetSelectedValue(fontDrop, g.fontKey)

            -- richtigen Label-Text zur aktuellen fontKey finden
            local label = g.fontKey
            if fontChoices then
                for _, data in ipairs(fontChoices) do
                    if data.key == g.fontKey then
                        label = data.label
                        break
                    end
                end
            end

            -- Text im Dropdown setzen (verhindert "Custom")
            UIDropDownMenu_SetText(fontDrop, label)
        end
           -- Global font dropdown
        if fontDrop and g.fontKey then
            -- sicherstellen, dass die Font-Liste existiert
            if (not fontChoices or #fontChoices == 0) and MSUF_RebuildFontChoices then
                MSUF_RebuildFontChoices()
            end

            UIDropDownMenu_SetSelectedValue(fontDrop, g.fontKey)

            local label = g.fontKey
            if fontChoices then
                for _, data in ipairs(fontChoices) do
                    if data.key == g.fontKey then
                        label = data.label
                        break
                    end
                end
            end

            UIDropDownMenu_SetText(fontDrop, label)
        end

        -- Font color style dropdown
        if fontColorDrop and g.fontColor then
            local key   = g.fontColor or "white"
            local label = key

            -- passenden Label-Text aus MSUF_COLOR_LIST holen
            for _, c in ipairs(MSUF_COLOR_LIST) do
                if c.key == key then
                    label = c.label
                    break
                end
            end

            UIDropDownMenu_SetSelectedValue(fontColorDrop, key)
            UIDropDownMenu_SetText(fontColorDrop, label)
        end

        if nameFontSizeSlider then
            nameFontSizeSlider:SetValue(g.nameFontSize or g.fontSize or 14)
        end
        if hpFontSizeSlider then
            hpFontSizeSlider:SetValue(g.hpFontSize or g.fontSize or 14)
        end
        if powerFontSizeSlider then
            powerFontSizeSlider:SetValue(g.powerFontSize or g.fontSize or 14)
        end
        if fontSizeSlider then
            fontSizeSlider:SetValue(g.fontSize or 14)
        end

        if highlightEnableCheck then
            highlightEnableCheck:SetChecked(g.highlightEnabled ~= false)
        end

        -- Mouseover highlight color dropdown
        if highlightColorDrop then
            local colorKey = g.highlightColor
            if type(colorKey) ~= "string" or not MSUF_FONT_COLORS[colorKey] then
                colorKey = "white"
                g.highlightColor = colorKey
            end

            -- Value setzen
            UIDropDownMenu_SetSelectedValue(highlightColorDrop, colorKey)

            -- passenden Label-Text aus MSUF_COLOR_LIST holen
            local label = colorKey
            if MSUF_COLOR_LIST then
                for _, opt in ipairs(MSUF_COLOR_LIST) do
                    if opt.key == colorKey then
                        label = opt.label
                        break
                    end
                end
            end

            -- Text im Feld setzen (verhindert "Custom")
            UIDropDownMenu_SetText(highlightColorDrop, label)
        end

        --------------------------------------------------
        -- Castbar Offsets / Sizes
        --------------------------------------------------
        if castbarTargetOffsetXSlider then
            castbarTargetOffsetXSlider:SetValue(g.castbarTargetOffsetX or 65)
        end
        if castbarTargetOffsetYSlider then
            castbarTargetOffsetYSlider:SetValue(g.castbarTargetOffsetY or -15)
        end
        if castbarFocusOffsetXSlider then
            castbarFocusOffsetXSlider:SetValue(g.castbarFocusOffsetX or g.castbarTargetOffsetX or 65)
        end
        if castbarFocusOffsetYSlider then
            castbarFocusOffsetYSlider:SetValue(g.castbarFocusOffsetY or g.castbarTargetOffsetY or -15)
        end
        if castbarPlayerOffsetXSlider then
            castbarPlayerOffsetXSlider:SetValue(g.castbarPlayerOffsetX or 0)
        end
        if castbarPlayerOffsetYSlider then
            castbarPlayerOffsetYSlider:SetValue(g.castbarPlayerOffsetY or 5)
        end
        if self.castbarPlayerTimeOffsetXSlider then
            self.castbarPlayerTimeOffsetXSlider:SetValue(g.castbarPlayerTimeOffsetX or -2)
        end
        if self.castbarPlayerTimeOffsetYSlider then
            self.castbarPlayerTimeOffsetYSlider:SetValue(g.castbarPlayerTimeOffsetY or 0)
        end

        -- Target/Focus/Player castbar sizes
        if castbarTargetBarWidthSlider then
            castbarTargetBarWidthSlider:SetValue(g.castbarTargetBarWidth or (g.castbarGlobalWidth or 250))
        end
        if castbarTargetBarHeightSlider then
            castbarTargetBarHeightSlider:SetValue(g.castbarTargetBarHeight or (g.castbarGlobalHeight or 18))
        end
        if castbarFocusBarWidthSlider then
            castbarFocusBarWidthSlider:SetValue(g.castbarFocusBarWidth or (g.castbarGlobalWidth or 250))
        end
        if castbarFocusBarHeightSlider then
            castbarFocusBarHeightSlider:SetValue(g.castbarFocusBarHeight or (g.castbarGlobalHeight or 18))
        end
        if castbarPlayerBarWidthSlider then
            castbarPlayerBarWidthSlider:SetValue(g.castbarPlayerBarWidth or (g.castbarGlobalWidth or 250))
        end
        if castbarPlayerBarHeightSlider then
            castbarPlayerBarHeightSlider:SetValue(g.castbarPlayerBarHeight or (g.castbarGlobalHeight or 18))
        end

        --------------------------------------------------
        -- Target aura bar positioning
        --------------------------------------------------
        if targetAuraWidthSlider then
            targetAuraWidthSlider:SetValue(g.targetAuraWidth or 200)
        end
        if targetAuraHeightSlider then
            targetAuraHeightSlider:SetValue(g.targetAuraHeight or 18)
        end
        if targetAuraScaleSlider then
            targetAuraScaleSlider:SetValue(g.targetAuraScale or 1)
        end
        if targetAuraAlphaSlider then
            targetAuraAlphaSlider:SetValue(g.targetAuraAlpha or 1)
        end
        if targetAuraXOffsetSlider then
            targetAuraXOffsetSlider:SetValue(g.targetAuraOffsetX or 0)
        end
        if targetAuraYOffsetSlider then
            targetAuraYOffsetSlider:SetValue(g.targetAuraOffsetY or 2)
        end

                --------------------------------------------------
        -- Aura display dropdown (Buffs/Debuffs ON/OFF)
        --------------------------------------------------
        if auraDisplayDrop then
            local key = g.targetAuraDisplay
            if type(key) ~= "string" or key == "" then
                key = "BUFFS_AND_DEBUFFS"
                g.targetAuraDisplay = key
            end

            -- Wert im Dropdown setzen
            UIDropDownMenu_SetSelectedValue(auraDisplayDrop, key)

            -- passenden Label-Text suchen
            local label = key
            if auraDisplayOptions then
                for _, opt in ipairs(auraDisplayOptions) do
                    if opt.key == key then
                        label = opt.label
                        break
                    end
                end
            end

            -- Text im Feld setzen (verhindert "Custom")
            UIDropDownMenu_SetText(auraDisplayDrop, label)
        end


        --------------------------------------------------
        -- Castbar toggles
        --------------------------------------------------
        if castbarTargetCheck then
            castbarTargetCheck:SetChecked(g.enableTargetCastbar ~= false)
        end
        if castbarFocusCheck then
            castbarFocusCheck:SetChecked(g.enableFocusCastbar ~= false)
        end
        if castbarPlayerEnableCheck then
            castbarPlayerEnableCheck:SetChecked(g.enablePlayerCastbar ~= false)
        end
        if castbarIconCheck then
            castbarIconCheck:SetChecked(g.castbarShowIcon ~= false)
        end
        if castbarSpellNameCheck then
            castbarSpellNameCheck:SetChecked(g.castbarShowSpellName ~= false)
        end
        castbarInterruptShakeCheck = _G["MSUF_CastbarInterruptShakeCheck"]
        if castbarInterruptShakeCheck then
            castbarInterruptShakeCheck:SetChecked(g.castbarInterruptShake ~= false)
        end
        if castbarSpellNameFontSizeSlider then
            castbarSpellNameFontSizeSlider:SetValue(g.castbarSpellNameFontSize or 0)
        end
        if castbarIconOffsetXSlider then
            castbarIconOffsetXSlider:SetValue(g.castbarIconOffsetX or 0)
        end
        if castbarIconOffsetYSlider then
            castbarIconOffsetYSlider:SetValue(g.castbarIconOffsetY or 0)
        end
            if castbarGracePeriodSlider then
            castbarGracePeriodSlider:SetValue(g.castbarGraceMs or 120)
        end
        --------------------------------------------------
        -- Global font toggles
        --------------------------------------------------
        if boldCheck then
            boldCheck:SetChecked(g.boldText and true or false)
        end
        if nameClassColorCheck then
            nameClassColorCheck:SetChecked(g.nameClassColor and true or false)
        end
        if npcNameRedCheck then
            npcNameRedCheck:SetChecked(g.npcNameRed and true or false)
        end
        if shortenNamesCheck then
            shortenNamesCheck:SetChecked(MSUF_DB.shortenNames and true or false)
        end
        if textBackdropCheck then
            textBackdropCheck:SetChecked(g.textBackdrop and true or false)
        end

        --------------------------------------------------
        -- Bars tab
        --------------------------------------------------
        if gradientCheck then
            gradientCheck:SetChecked(g.enableGradient ~= false)
        end
        if gradientSlider then
            v = math.floor((g.gradientStrength or 0.45) * 100 + 0.5)
            gradientSlider:SetValue(v)
        end

        local function ApplyBarCheck(cb, key)
            if not cb then return end
            enabled = true
            if bars[key] ~= nil then
                enabled = bars[key] and true or false
            end
            cb:SetChecked(enabled)
        end

        ApplyBarCheck(targetPowerBarCheck, "showTargetPowerBar")
        ApplyBarCheck(bossPowerBarCheck,   "showBossPowerBar")
        ApplyBarCheck(playerPowerBarCheck, "showPlayerPowerBar")
        ApplyBarCheck(focusPowerBarCheck,  "showFocusPowerBar")

        if powerBarHeightEdit then
            h = 3
            if type(bars.powerBarHeight) == "number" and bars.powerBarHeight > 0 then
                h = bars.powerBarHeight
            end
            powerBarHeightEdit:SetText(tostring(h))
        end
        -- Bar mode dropdown (Dark/Class)
        if barModeDrop then
            local mode = g.barMode

            -- Kompatibel zu alten Flags (darkMode/useClassColors)
            if mode ~= "dark" and mode ~= "class" then
                if g.useClassColors then
                    mode = "class"
                else
                    mode = "dark"
                end
                g.barMode = mode
            end

            UIDropDownMenu_SetSelectedValue(barModeDrop, mode)

            -- Label passend zur Auswahl suchen
            local label = mode
            if barModeOptions then
                for _, opt in ipairs(barModeOptions) do
                    if opt.key == mode then
                        label = opt.label
                        break
                    end
                end
            end

            UIDropDownMenu_SetText(barModeDrop, label)
        end

        -- Dark mode bar color dropdown
        if darkToneDrop then
            local toneKey = g.darkBarTone
            if type(toneKey) ~= "string" or toneKey == "" then
                toneKey = "black"
                g.darkBarTone = toneKey
            end

            UIDropDownMenu_SetSelectedValue(darkToneDrop, toneKey)

            local toneLabel = toneKey
            if darkToneChoices then
                for _, opt in ipairs(darkToneChoices) do
                    if opt.key == toneKey then
                        toneLabel = opt.label
                        break
                    end
                end
            end
            UIDropDownMenu_SetText(darkToneDrop, toneLabel)
        end

        -- Bar texture (SharedMedia) dropdown
        if barTextureDrop then
            local texKey = g.barTexture
            if type(texKey) ~= "string" or texKey == "" then
                texKey = "Blizzard"
                g.barTexture = texKey
            end

            -- Wert + sichtbaren Text setzen → verhindert leeres Feld / "Custom"
            UIDropDownMenu_SetSelectedValue(barTextureDrop, texKey)
            UIDropDownMenu_SetText(barTextureDrop, texKey)

        elseif MSUF_UpdateBarTextureDropdown then
            -- Fallback, falls aus irgendeinem Grund kein Dropdown existiert
            MSUF_UpdateBarTextureDropdown()
        end

        if darkBgBrightnessSlider then
            local v = g.darkBgBrightness or 0.25
            v = math.floor(v * 100 + 0.5)
            if v < 1  then v = 1  end
            if v > 99 then v = 99 end
            darkBgBrightnessSlider:SetValue(v)
        end


        if borderCheck then
            enabled = true
            if g.useBarBorder == false then
                enabled = false
            end
            if bars.showBarBorder ~= nil then
                enabled = (bars.showBarBorder ~= false)
            end
            borderCheck:SetChecked(enabled)
        end
        -- Bar border style dropdown
        if borderDrop then
            local key = g.barBorderStyle
            if type(key) ~= "string" then
                key = "THIN"
                g.barBorderStyle = key
            end

            -- Value setzen
            UIDropDownMenu_SetSelectedValue(borderDrop, key)

            -- passenden Label-Text suchen
            local label = key
            if borderOptions then
                for _, opt in ipairs(borderOptions) do
                    if opt.key == key then
                        label = opt.label
                        break
                    end
                end
            end

            -- Text im Feld setzen (verhindert leeres Feld / "Custom")
            UIDropDownMenu_SetText(borderDrop, label)
        end

        --------------------------------------------------
        
        -- Boss spacing slider visibility (only for Boss Frames)
if bossSpacingSlider then
    if currentKey == "boss" then
        bossSpacingSlider:Show()
        if bossSpacingSlider.editBox then
            bossSpacingSlider.editBox:Show()
        end
    else
        bossSpacingSlider:Hide()
        if bossSpacingSlider.editBox then
            bossSpacingSlider.editBox:Hide()
        end
    end
end

        --------------------------------------------------
        -- Unit-specific settings
        --------------------------------------------------
        if currentKey == "fonts" or currentKey == "bars" or currentKey == "misc" or currentKey == "profiles" then
            return
        end

        conf = MSUF_DB[currentKey]
        if not conf then return end

        -- Boss spacing slider value (Boss Frames only)
        if bossSpacingSlider and currentKey == "boss" then
            bossSpacingSlider:SetValue(conf.spacing or -36)
        end

        -- For Player/Target/Focus/ToT/Pet we hide width/height sliders
        hideSizeSliders =
            (currentKey == "player"
             or currentKey == "target"
             or currentKey == "focus"
             or currentKey == "targettarget"
             or currentKey == "pet")
    if widthSlider then
        wText = _G["MSUF_WidthSliderText"]
        wLow = _G["MSUF_WidthSliderLow"]
        wHigh = _G["MSUF_WidthSliderHigh"]

        -- Width-Slider ausblenden für player/target/focus/tot/pet UND boss
        hideWidth = hideSizeSliders or (currentKey == "boss")

        if hideWidth then
            widthSlider:Hide()
            if widthSlider.editBox     then widthSlider.editBox:Hide()     end
            if widthSlider.minusButton then widthSlider.minusButton:Hide() end
            if widthSlider.plusButton  then widthSlider.plusButton:Hide()  end
            if wText  then wText:Hide()  end
            if wLow   then wLow:Hide()   end
            if wHigh  then wHigh:Hide()  end
        else
            widthSlider:Show()
            if widthSlider.editBox     then widthSlider.editBox:Show()     end
            if widthSlider.minusButton then widthSlider.minusButton:Show() end
            if widthSlider.plusButton  then widthSlider.plusButton:Show()  end
            if wText  then wText:Show()  end
            if wLow   then wLow:Show()   end
            if wHigh  then wHigh:Show()  end

            widthSlider:SetValue(conf.width or 250)
        end
    end

     if heightSlider then
        hText = _G["MSUF_HeightSliderText"]
        hLow = _G["MSUF_HeightSliderLow"]
        hHigh = _G["MSUF_HeightSliderHigh"]

        -- Height-Slider ausblenden für player/target/focus/tot/pet UND boss
        hideHeight = hideSizeSliders or (currentKey == "boss")

        if hideHeight then
            heightSlider:Hide()
            if heightSlider.editBox     then heightSlider.editBox:Hide()     end
            if heightSlider.minusButton then heightSlider.minusButton:Hide() end
            if heightSlider.plusButton  then heightSlider.plusButton:Hide()  end
            if hText  then hText:Hide()  end
            if hLow   then hLow:Hide()   end
            if hHigh  then hHigh:Hide()  end
        else
            heightSlider:Show()
            if heightSlider.editBox     then heightSlider.editBox:Show()     end
            if heightSlider.minusButton then heightSlider.minusButton:Show() end
            if heightSlider.plusButton  then heightSlider.plusButton:Show()  end
            if hText  then hText:Show()  end
            if hLow   then hLow:Show()   end
            if hHigh  then hHigh:Show()  end

            heightSlider:SetValue(conf.height or 40)
        end
    end
        if xSlider then
            xSlider:SetValue(conf.offsetX or 0)
            xSlider:Hide()
            if xSlider.editBox then xSlider.editBox:Hide() end
            if xSlider.minusButton then xSlider.minusButton:Hide() end
            if xSlider.plusButton then xSlider.plusButton:Hide() end
        end
        if ySlider then
            ySlider:SetValue(conf.offsetY or 0)
            ySlider:Hide()
            if ySlider.editBox then ySlider.editBox:Hide() end
            if ySlider.minusButton then ySlider.minusButton:Hide() end
            if ySlider.plusButton then ySlider.plusButton:Hide() end
        end

        if showNameCB then
            showNameCB:SetChecked(conf.showName ~= false)
        end
        if showHPCB then
            showHPCB:SetChecked(conf.showHP ~= false)
        end
        if showPowerCB then
            showPowerCB:SetChecked(conf.showPower ~= false)
        end
        if enableFrameCB then
            enableFrameCB:SetChecked(conf.enabled ~= false)
        end

        if nameOffsetXSlider then
            nameOffsetXSlider:SetValue(conf.nameOffsetX or 4)
        end
        if nameOffsetYSlider then
            nameOffsetYSlider:SetValue(conf.nameOffsetY or -4)
        end
        if hpOffsetXSlider then
            hpOffsetXSlider:SetValue(conf.hpOffsetX or -4)
        end
        if hpOffsetYSlider then
            hpOffsetYSlider:SetValue(conf.hpOffsetY or -4)
        end
        if powerOffsetXSlider then
            powerOffsetXSlider:SetValue(conf.powerOffsetX or -4)
        end
        if powerOffsetYSlider then
            powerOffsetYSlider:SetValue(conf.powerOffsetY or 4)
        end
    end
    --------------------------------------------------
    -- SLIDER CALLBACKS (frame settings)
    --------------------------------------------------
    widthSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.width = value
        ApplySettingsForKey(currentKey)
    end

    heightSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.height = value
        ApplySettingsForKey(currentKey)
    end

    -- Boss spacing slider: controls distance between boss frames
if bossSpacingSlider then
    if currentKey == "boss" then
        bossSpacingSlider:Show()
        if bossSpacingSlider.editBox     then bossSpacingSlider.editBox:Show()     end
        if bossSpacingSlider.minusButton then bossSpacingSlider.minusButton:Show() end
        if bossSpacingSlider.plusButton  then bossSpacingSlider.plusButton:Show()  end

        -- Wert aus der DB ins UI
        bossSpacingSlider:SetValue(conf.spacing or -36)
    else
        bossSpacingSlider:Hide()
        if bossSpacingSlider.editBox     then bossSpacingSlider.editBox:Hide()     end
        if bossSpacingSlider.minusButton then bossSpacingSlider.minusButton:Hide() end
        if bossSpacingSlider.plusButton  then bossSpacingSlider.plusButton:Hide()  end
    end
end


    xSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.offsetX = value
        ApplySettingsForKey(currentKey)
    end

    ySlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.offsetY = value
        ApplySettingsForKey(currentKey)
    end

    showNameCB:SetScript("OnClick", function(self)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.showName = self:GetChecked() and true or false
        ApplySettingsForKey(currentKey)
    end)

    showHPCB:SetScript("OnClick", function(self)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.showHP = self:GetChecked() and true or false
        ApplySettingsForKey(currentKey)
    end)

    showPowerCB:SetScript("OnClick", function(self)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.showPower = self:GetChecked() and true or false
        ApplySettingsForKey(currentKey)
    end)

    enableFrameCB:SetScript("OnClick", function(self)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.enabled = self:GetChecked() and true or false
        ApplySettingsForKey(currentKey)
    end)

    panel.nameOffsetXSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.nameOffsetX = value
        ApplySettingsForKey(currentKey)
    end

    panel.nameOffsetYSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.nameOffsetY = value
        ApplySettingsForKey(currentKey)
    end

    panel.hpOffsetXSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.hpOffsetX = value
        ApplySettingsForKey(currentKey)
    end

    panel.hpOffsetYSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.hpOffsetY = value
        ApplySettingsForKey(currentKey)
    end

    panel.powerOffsetXSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.powerOffsetX = value
        ApplySettingsForKey(currentKey)
    end

    panel.powerOffsetYSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.powerOffsetY = value
        ApplySettingsForKey(currentKey)
    end

    --------------------------------------------------
    -- GENERAL TOGGLES
    --------------------------------------------------
    -- anchorCheck OnClick handler removed (anchor toggle only in Edit Mode)

 -- Dark Mode: schaltet Class Color aus, wenn aktiviert
--------------------------------------------------
    -- INIT
    --------------------------------------------------
    SetCurrentKey("player")
    panel:LoadFromDB()
    UpdateAllFonts()

    -- Kategorie registrieren und global merken, damit wir sie z.B. vom Minimap-Button öffnen können
    MSUF_SettingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(MSUF_SettingsCategory)
end
------------------------------------------------------
-- Force panel to load DB when shown (fix for Custom/empty fields)
------------------------------------------------------
if panel and panel.LoadFromDB and not panel.__MSUF_OnShowHooked then
    panel.__MSUF_OnShowHooked = true
    panel:SetScript("OnShow", function(self)
        if self.LoadFromDB then
            self:LoadFromDB()
        end
    end)
end

------------------------------------------------------
-- OPTIONS ÖFFNEN (wird vom Minimap-Button benutzt)
------------------------------------------------------
local function MSUF_OpenOptionsMenu()
    -- Neuer Settings-Frame (Dragonflight+)
    if Settings and Settings.OpenToCategory and MSUF_SettingsCategory then
        Settings.OpenToCategory(MSUF_SettingsCategory)
        return
    end

    -- Fallback für ältere Clients
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory("Midnight Simple Unit Frames Alpha")
    end
end

------------------------------------------------------
-- Einfacher Minimap-Button
------------------------------------------------------
local function MSUF_CreateMinimapButton()
    if MSUF_MinimapButton or not Minimap then
        return
    end

    btn = CreateFrame("Button", "MSUF_MinimapButton", Minimap)
    MSUF_MinimapButton = btn

    -- etwas kleiner & moderner
    btn:SetSize(24, 24)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 5)

    -- Startposition (kann danach frei verschoben werden)
    btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 4, -4)

    -- Bewegbar machen
    btn:SetMovable(true)
    btn:SetUserPlaced(true)
    btn:SetClampedToScreen(true)
    -- Rechtsklick halten und ziehen zum Verschieben
    btn:RegisterForDrag("RightButton")
    btn:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    -- Icon: dunkles Kräuter/Blumen-Icon
    icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Ability_Rogue_CloakOfShadows")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetAllPoints()
    btn.icon = icon

    -- dezentes Highlight beim Hovern
    hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Midnight Simple Unit Frames", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Open options", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click + drag: Move button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Klick: Links öffnet das MSUF-Optionsmenü
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            MSUF_OpenOptionsMenu()
        end
    end)
end

------------------------------------------------------
-- HOOK COOLDOWN VIEWER
------------------------------------------------------

local function HookCooldownViewer()
    EnsureDB()

    g = MSUF_DB.general or {}

    -- Feature ist deaktiviert → nichts tun
    if not g.anchorToCooldown then
        return
    end

-- Versuche, den Cooldown-Frame zu finden (immer EssentialCooldownViewer)
ecv = _G["EssentialCooldownViewer"]

    -- Kein Cooldown-Addon da → einfach nicht hooken.
    -- Die Warnung übernimmt MSUF_CheckCooldownAddon().
    if not ecv then
        return
    end

    if ecv.MSUFHooked then
        return
    end
    ecv.MSUFHooked = true

    local function realign()
        -- Im Kampf nichts verschieben, sonst Taint
        if InCombatLockdown() then
            return
        end

        if UnitFrames.player       then PositionUnitFrame(UnitFrames.player,       "player")       end
        if UnitFrames.target       then PositionUnitFrame(UnitFrames.target,       "target")       end
        if UnitFrames.targettarget then PositionUnitFrame(UnitFrames.targettarget, "targettarget") end
        if UnitFrames.focus        then PositionUnitFrame(UnitFrames.focus,        "focus")        end
    end

    ecv:HookScript("OnSizeChanged", realign)
    ecv:HookScript("OnShow",        realign)
    ecv:HookScript("OnHide",        realign)

    realign()
end

------------------------------------------------------

------------------------------------------------------
-- FIRST-RUN SETUP WIZARD (per character, optional)
------------------------------------------------------
function MSUF_SetCooldownViewerEnabled(enabled)
    if not SetCVar then
        return
    end
    if enabled then
        SetCVar("cooldownViewerEnabled", "1")
    else
        SetCVar("cooldownViewerEnabled", "0")
    end
end

local MSUF_SetupFrame
MSUF_SetupCurrentStep = 1
MSUF_SetupIsRunning = false

-- Simple helper to get (and ensure) the per-character entry in MSUF_GlobalDB.char
local function MSUF_GetCharEntryForSetup()
    if not MSUF_GetCharKey then
        return nil
    end
    MSUF_GlobalDB = MSUF_GlobalDB or {}
    MSUF_GlobalDB.char = MSUF_GlobalDB.char or {}

    key = MSUF_GetCharKey()
    char = MSUF_GlobalDB.char[key] or {}
    MSUF_GlobalDB.char[key] = char
    return char
end

local function MSUF_HasSeenSetupForChar()
    char = MSUF_GetCharEntryForSetup()
    if not char then return false end
    return char.setupDone == true
end

local function MSUF_MarkSetupDoneForChar()
    char = MSUF_GetCharEntryForSetup()
    if not char then return end
    char.setupDone = true
end

-- Text content for the tiny onboarding wizard
-- Texture used in the setup wizard (drop your file into Media with this name)
local MSUF_SETUP_POPUP_TEXTURE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\MSUF_EditPopup"

-- Text content for the tiny onboarding wizard
MSUF_SETUP_STEPS = {
    {
        title = "Welcome to Midnight Simple Unit Frames",
        text  = "This short wizard shows you the basics of the MSUF Edit Mode.\n\n" ..
                "You can always rerun it later with |cffffd700/msuf setup|r."
    },
    {
        title = "Step 1: Move & resize frames",
        text  = "In MSUF Edit Mode each unitframe gets arrow handles.\n\n" ..
                "- Drag the center block to move the frame.\n" ..
                "- Use |cffffd700Size|r mode to resize health, power and castbars."
    },
    {
        title = "Step 2: Precise values (popup)",
        text  = "Rightclick on an arrow to open the MSUF Edit popup in order to fine-tune your layout.\n\n" ..
                "Here you can type exact offsets and sizes or use the +/- buttons for small steps.",
        image = MSUF_SETUP_POPUP_TEXTURE,   -- <- zeigt dein Bild an
    },
}
local function MSUF_Setup_UpdateStep()
    if not MSUF_SetupFrame then return end

    local step = MSUF_SETUP_STEPS[MSUF_SetupCurrentStep]
    if not step then return end

    MSUF_SetupFrame.title:SetText(step.title or "")
    MSUF_SetupFrame.text:SetText(step.text or "")
    MSUF_SetupFrame.stepLabel:SetText(string.format("Step %d / %d", MSUF_SetupCurrentStep, #MSUF_SETUP_STEPS))

    -- Optionales Bild pro Step
    if MSUF_SetupFrame.image then
        if step.image then
            MSUF_SetupFrame.image:SetTexture(step.image)
            MSUF_SetupFrame.image:Show()
        else
            MSUF_SetupFrame.image:Hide()
        end
    end


    if MSUF_SetupCurrentStep <= 1 then
        MSUF_SetupFrame.backButton:Disable()
    else
        MSUF_SetupFrame.backButton:Enable()
    end

    if MSUF_SetupCurrentStep >= #MSUF_SETUP_STEPS then
        MSUF_SetupFrame.nextButton:SetText("Finish")
    else
        MSUF_SetupFrame.nextButton:SetText("Next")
    end
end

local function MSUF_Setup_CreateFrame()
    if MSUF_SetupFrame then
        return MSUF_SetupFrame
    end

        local f = CreateFrame("Frame", "MSUF_SetupWizardFrame", UIParent, "BackdropTemplate")
    MSUF_SetupFrame = f

    f:SetSize(520, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile     = true, tileSize = 16, edgeSize = 16,
            insets   = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.9)
    end

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -16)
    title:SetJustifyH("LEFT")
    f.title = title

    local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function()
        MSUF_MarkSetupDoneForChar()
        MSUF_SetupIsRunning = false
        f:Hide()
    end)

    local body = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -12)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    f.text = body

        -- Optionales Vorschaubild (z.B. Edit-Popup)
    local image = f:CreateTexture(nil, "ARTWORK")
    image:SetPoint("TOP", body, "BOTTOM", 0, -8)
    image:SetSize(300, 218)  -- passend zu deinem Screenshot
    image:Hide()
    f.image = image

    local stepLabel = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    stepLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
    stepLabel:SetJustifyH("LEFT")
    f.stepLabel = stepLabel

    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    hint:SetJustifyH("RIGHT")
    hint:SetText("You can always rerun this via  /msuf setup")
    f.hint = hint

    local backButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    backButton:SetSize(80, 24)
    backButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -190, 16)
    backButton:SetText("Back")
    backButton:SetScript("OnClick", function()
        if MSUF_SetupCurrentStep > 1 then
            MSUF_SetupCurrentStep = MSUF_SetupCurrentStep - 1
            MSUF_Setup_UpdateStep()
        end
    end)
    f.backButton = backButton

    local nextButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextButton:SetSize(100, 24)
    nextButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -100, 16)
    nextButton:SetText("Next")
    nextButton:SetScript("OnClick", function()
        if MSUF_SetupCurrentStep < #MSUF_SETUP_STEPS then
            MSUF_SetupCurrentStep = MSUF_SetupCurrentStep + 1
            MSUF_Setup_UpdateStep()
        else
            -- Finish
            MSUF_MarkSetupDoneForChar()
            MSUF_SetupIsRunning = false
            f:Hide()
        end
    end)
    f.nextButton = nextButton

    local skipButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    skipButton:SetSize(80, 24)
    skipButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    skipButton:SetText("Skip")
    skipButton:SetScript("OnClick", function()
        -- Mark setup as done so it does not auto-open again
        MSUF_MarkSetupDoneForChar()
        MSUF_SetupIsRunning = false
        f:Hide()
    end)
    f.skipButton = skipButton

    return f
end

-- Helper that tries to open options + force Edit Mode ON
local function MSUF_Setup_EnterEditMode()
    -- Open the MSUF options (Settings-based on DF+ or InterfaceOptions fallback)
    if MSUF_OpenOptionsMenu then
        MSUF_OpenOptionsMenu()
    end

    -- Small delay so the panel has time to open before we toggle Edit Mode
    local function toggle()
        btn = _G["MSUF_EditModeButton"]
        if btn and btn:GetScript("OnClick") and not MSUF_UnitEditModeActive then
            btn:GetScript("OnClick")(btn)
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, toggle)
    else
        toggle()
    end
end

local function MSUF_BeginSetupWizard(manual)
    if MSUF_SetupIsRunning then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        print("|cffffd700MSUF:|r Setup cannot start while in combat.")
        return
    end

    -- Ensure Blizzard cooldown viewer is enabled when running the setup
    MSUF_SetCooldownViewerEnabled(true)

    MSUF_SetupIsRunning = true
    MSUF_SetupCurrentStep = 1

    -- Open options + Edit Mode, then show the wizard window slightly delayed
    MSUF_Setup_EnterEditMode()

    local function showWizard()
        frame = MSUF_Setup_CreateFrame()
        frame:Show()
        MSUF_Setup_UpdateStep()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.6, showWizard)
    else
        showWizard()
    end
end

-- Called automatically after login (PLAYER_LOGIN) to decide if we should run the wizard
local function MSUF_CheckAndRunFirstSetup()
    -- Only once per character
    if MSUF_HasSeenSetupForChar() then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        -- Safety: do not try to open setup in combat
        return
    end

    MSUF_BeginSetupWizard(false)
end

------------------------------------------------------
-- ADDON STARTUP
------------------------------------------------------
local main = CreateFrame("Frame")
main:RegisterEvent("PLAYER_LOGIN")

main:SetScript("OnEvent", function(self, event)
    MSUF_InitProfiles()
    EnsureDB()
    HideDefaultFrames()
    CreateSimpleUnitFrame("player")
    CreateSimpleUnitFrame("target")
    CreateSimpleUnitFrame("targettarget")
    CreateSimpleUnitFrame("focus")
    CreateSimpleUnitFrame("pet")
    for i = 1, MSUF_MAX_BOSS_FRAMES do
        CreateSimpleUnitFrame("boss" .. i)
    end

    -- Fallback: Target-of-Target regelmäßig updaten, falls Events zicken
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.10, function()
            local tot = UnitFrames and UnitFrames["targettarget"]
            if tot and UnitExists and UnitExists("targettarget") then
                UpdateSimpleUnitFrame(tot)
            end
        end)
    end

    ApplyAllSettings()
    MSUF_ReanchorTargetCastBar()
    MSUF_ReanchorFocusCastBar()


    if TargetFrameSpellBar and not TargetFrameSpellBar.MSUF_Hooked then
        TargetFrameSpellBar.MSUF_Hooked = true
        TargetFrameSpellBar:HookScript("OnShow", function()
            MSUF_ReanchorTargetCastBar()
        end)
        TargetFrameSpellBar:HookScript("OnEvent", function()
            MSUF_ReanchorTargetCastBar()
        end)
    end

    if FocusFrameSpellBar and not FocusFrameSpellBar.MSUF_Hooked then
        FocusFrameSpellBar.MSUF_Hooked = true
        FocusFrameSpellBar:HookScript("OnShow", function()
            MSUF_ReanchorFocusCastBar()
        end)
        FocusFrameSpellBar:HookScript("OnEvent", function()
            MSUF_ReanchorFocusCastBar()
        end)
    end

-- Always hide Blizzard's pet castbar (no custom MSUF pet castbar)
if PetCastingBarFrame then
    if not PetCastingBarFrame.MSUF_HideHooked then
        PetCastingBarFrame.MSUF_HideHooked = true
        hooksecurefunc(PetCastingBarFrame, "Show", function(self)
            self:Hide()
        end)
    end
    PetCastingBarFrame:Hide()
end

    -- NEU: Blizzard Options-Panel bewegbar machen
    C_Timer.After(0.5, MSUF_MakeBlizzardOptionsMovable)

    CreateOptionsPanel()

    -- Einfaches Minimap-Icon nach dem Erzeugen des Options-Panels (damit MSUF_SettingsCategory existiert)
    MSUF_CreateMinimapButton()

    MSUF_CheckAndRunFirstSetup()

    C_Timer.After(1, HookCooldownViewer)
    C_Timer.After(1.1, MSUF_InitPlayerCastbarPreviewToggle)

    print("|cff00ff00MSUF:|rBuild 1.0 Beta1. Have a great week gamer <3 report bugs in the Discord. No more new feature until 1.0 release just bugfixing.")
end)


------------------------------------------------------
-- Default reset values
------------------------------------------------------
local MSUF_RESET_DEFAULTS = {
    player = {
        width     = 275,
        height    = 40,
        offsetX   = -260,
        offsetY   = 80,
        showName  = true,
        showHP    = true,
        showPower = true,
    },
    target = {
        width     = 275,
        height    = 40,
        offsetX   = 260,
        offsetY   = 80,
        showName  = true,
        showHP    = true,
        showPower = true,
    },
    focus = {
        width     = 220,
        height    = 30,
        offsetX   = 260,
        offsetY   = 135,
        showName  = true,
        showHP    = false,
        showPower = false,
    },
    pet = {
        width     = 220,
        height    = 30,
        offsetX   = -260,
        offsetY   = 135,
        showName  = true,
        showHP    = false,
        showPower = false,
    },
    targettarget = {
        width     = 220,
        height    = 30,
        offsetX   = 260,
        offsetY   = 225,
        showName  = true,
        showHP    = true,
        showPower = false,
    },
}

------------------------------------------------------
-- FULL RESET (ALL SAVED VARIABLES)
------------------------------------------------------
local MSUF_FullResetPending = false

local function MSUF_DoFullReset()
    if InCombatLockdown and InCombatLockdown() and InCombatLockdown() then
        print("|cffff0000MSUF:|r Cannot do FULL reset while in combat.")
        return
    end

    -- Alles weghauen: Accountweite SavedVariables für MSUF
    MSUF_DB           = nil
    MSUF_GlobalDB     = nil
    MSUF_ActiveProfile = nil

    print("|cffff0000MSUF:|r FULL RESET executed – all MSUF profiles & settings deleted for this account.")
    print("|cffffff00MSUF:|r Reloading UI to rebuild clean defaults...")

    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, ReloadUI)
    else
        ReloadUI()
    end
end

------------------------------------------------------
-- SLASH: /msuf commands
------------------------------------------------------
-- Zentraler Help-Printer für /msuf und !msuf help
local function MSUF_PrintHelp()
    print("|cff00ff00MSUF commands:|r")
    print("  /msuf reset     - Reset all MSUF frame positions and visibility to defaults.")
    print("  /msuf fullreset - FULL factory reset (all profiles/settings, needs confirmation).")
    print("  /msuf setup     - Rerun the first-run setup wizard (opens options + Edit Mode).")
    print("  /msuf absorb    - Toggle showing total absorb amount in HP text (may show +0 at 0 absorb due to Blizzard API).")
    print("  /msuf profiler  - Toggle performance profiler ON/OFF (shortcut for /msufprofile on/off).")
    print("  /msufprofile    - Profiler details: /msufprofile on, off, reset, show.")
    print("  !msuf help      - Print this help via chat.")
end

SLASH_MIDNIGHTSUF1 = "/msuf"
SlashCmdList["MIDNIGHTSUF"] = function(msg)
    msg = msg and msg:lower() or ""

    -- erstes Wort als Command extrahieren (z.B. "reset", "absorb", "help")
    local cmd = msg:match("^(%S+)")
    cmd = cmd or ""

    -- /msuf oder /msuf help -> nur Help
    if cmd == "" or cmd == "help" then
        MSUF_PrintHelp()
        return
    end
        --------------------------------------------------
    -- /msuf fullreset  -> EVERYTHING wiped (2-step confirm)
    --------------------------------------------------
    if cmd == "fullreset" then
        -- 1. Stufe: nur warnen und Confirmation verlangen
        if not MSUF_FullResetPending then
            MSUF_FullResetPending = true
            print("|cffff0000MSUF WARNING:|r This will delete |cffff0000ALL|r MSUF profiles & settings for this account.")
            print("|cffffcc00MSUF:|r Type |cffffff00/msuf fullreset confirm|r if you really want to do this.")
            return
        end

        -- 2. Stufe: User muss exakt "/msuf fullreset confirm" getippt haben
        if msg ~= "fullreset confirm" then
            MSUF_FullResetPending = false
            print("|cffffcc00MSUF:|r Full reset cancelled. If you still want it, type:")
            print("  /msuf fullreset")
            print("  /msuf fullreset confirm")
            return
        end

        MSUF_FullResetPending = false
        MSUF_DoFullReset()
        return
    end

--------------------------------------------------
-- Chat-Listener für !msuf help
--------------------------------------------------
local MSUF_ChatCommandFrame = CreateFrame("Frame")

-- Wir hören auf typische Text-Kanäle
MSUF_ChatCommandFrame:RegisterEvent("CHAT_MSG_SAY")
MSUF_ChatCommandFrame:RegisterEvent("CHAT_MSG_YELL")
MSUF_ChatCommandFrame:RegisterEvent("CHAT_MSG_PARTY")
MSUF_ChatCommandFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
MSUF_ChatCommandFrame:RegisterEvent("CHAT_MSG_RAID")
MSUF_ChatCommandFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
MSUF_ChatCommandFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
MSUF_ChatCommandFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
MSUF_ChatCommandFrame:RegisterEvent("CHAT_MSG_GUILD")
MSUF_ChatCommandFrame:RegisterEvent("CHAT_MSG_OFFICER")
MSUF_ChatCommandFrame:RegisterEvent("CHAT_MSG_WHISPER")

MSUF_ChatCommandFrame:SetScript("OnEvent", function(self, event, text, author, ...)
    if not text or not author then
        return
    end

    -- Nur reagieren, wenn die Nachricht von dir selbst kommt
    local myName = UnitName("player")
    local shortAuthor = author:match("^[^-]+") or author
    if shortAuthor ~= myName then
        return
    end

    -- Text normalisieren
    local msgLower = text:lower():gsub("^%s+", "")

    -- !msuf help am Zeilenanfang
    if msgLower == "!msuf help" or msgLower:match("^!msuf%s+help") then
        MSUF_PrintHelp()
    end
end)

   --------------------------------------------------

    --------------------------------------------------
    -- /msuf setup  -> run setup wizard again
    --------------------------------------------------
    if cmd == "setup" then
        MSUF_BeginSetupWizard(true)
        return
    end

    -- /msuf reset
    --------------------------------------------------
    if cmd == "reset" then
        if InCombatLockdown() then
            print("|cffff0000MSUF:|r Cannot reset while in combat.")
            return
        end

        EnsureDB()

        for unit, defaults in pairs(MSUF_RESET_DEFAULTS) do
            MSUF_DB[unit] = MSUF_DB[unit] or {}
            local t = MSUF_DB[unit]

            for k, v in pairs(defaults) do
                t[k] = v
            end

            if t.enabled == nil then
                t.enabled = true
            end
        end

        ApplyAllSettings()
        UpdateAllFonts()

        print("|cff00ff00MSUF:|r Positions and visibility reset to defaults.")
        return
    end

    --------------------------------------------------
    -- /msuf absorb  -> Absorb-Zahl im HP-Text togglen
    --------------------------------------------------
    if cmd == "absorb" then
        EnsureDB()
        local g = MSUF_DB.general or {}

        g.showTotalAbsorbAmount = not g.showTotalAbsorbAmount

        ApplyAllSettings()

        if g.showTotalAbsorbAmount then
            print("|cff00ff00MSUF:|r Total absorb amount in HP text ENABLED.")
            print("|cffffcc00MSUF:|r Will show +0 if you have 0 absorb due to Blizzard current API restrictions.")
        else
            print("|cff00ff00MSUF:|r Total absorb amount in HP text DISABLED.")
        end

        return
    end

    --------------------------------------------------
    -- /msuf profiler  -> Profiler ON/OFF togglen
    --------------------------------------------------
    if cmd == "profiler" then
        -- MSUF_ProfileEnabled ist ganz oben als lokale Funktion definiert,
        -- ns.MSUF_ProfileSetEnabled(flag) setzt das Flag + räumt auf.
        if MSUF_ProfileEnabled() then
            ns.MSUF_ProfileSetEnabled(false)
            print("|cffffd700MSUF:|r Profiler |cffff0000DISABLED|r.")
        else
            ns.MSUF_ProfileSetEnabled(true)
            MSUF_ProfileData = {}
            print("|cffffd700MSUF:|r Profiler |cff00ff00ENABLED|r.")
            print("|cffffcc00MSUF:|r Do some combat, then use /msufprofile to show the results.")
        end
        return
    end

    --------------------------------------------------
    -- Fallback: Unbekannter Subcommand -> Help anzeigen
    --------------------------------------------------
    MSUF_PrintHelp()
end
--------------------------------------------------

local MSUF_PlayerInfoFrame

local function MSUF_GetPlayerInfoFrame()
    if MSUF_PlayerInfoFrame then
        return MSUF_PlayerInfoFrame
    end

    local f = CreateFrame("Frame", "MSUF_PlayerInfoFrame", UIParent, "BackdropTemplate")
    f:SetSize(260, 90)
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -16, 180)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:EnableMouse(false)

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.9)
    end

    local nameFS = f:CreateFontString(nil, "OVERLAY", "GameTooltipHeaderText")
    nameFS:SetPoint("TOPLEFT", 8, -8)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetText("")
    nameFS:SetTextColor(1, 1, 1) -- Weiß wie normaler Tooltip-Text

    local line2FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line2FS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -2)
    line2FS:SetJustifyH("LEFT")

    local line3FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line3FS:SetPoint("TOPLEFT", line2FS, "BOTTOMLEFT", 0, -2)
    line3FS:SetJustifyH("LEFT")

    local line4FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line4FS:SetPoint("TOPLEFT", line3FS, "BOTTOMLEFT", 0, -2)
    line4FS:SetJustifyH("LEFT")

    local line5FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line5FS:SetPoint("TOPLEFT", line4FS, "BOTTOMLEFT", 0, -2)
    line5FS:SetJustifyH("LEFT")
    line5FS:SetTextColor(0.8, 0.8, 0.8) -- leicht ausgegraut wie Location-Zeile

    f.name  = nameFS
    f.line2 = line2FS
    f.line3 = line3FS
    f.line4 = line4FS
    f.line5 = line5FS

    f:Hide()
    MSUF_PlayerInfoFrame = f
    return f
end



local function MSUF_PositionPlayerInfoFrame(frame)
    EnsureDB()
    local g = MSUF_DB.general or {}
    local style = g.unitInfoTooltipStyle or "classic"

    frame:ClearAllPoints()

    if style == "modern" and GetCursorPosition and UIParent then
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        x, y = x / scale, y / scale

        -- 150px unter dem Mauszeiger, leicht nach links versetzt
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - 130, y - 150)
    else
        -- Blizzard-ähnliche Standardposition unten rechts
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -16, 180)
    end
end

function MSUF_ShowPlayerInfoTooltip()
    local f = MSUF_GetPlayerInfoFrame()
    if not UnitExists("player") then
        f:Hide()
        return
    end

    local name       = UnitName("player")
    local level      = UnitLevel("player")
    local race       = UnitRace("player")
    local classLoc   = select(1, UnitClass("player"))
    local faction    = UnitFactionGroup("player")
    local isPVP      = UnitIsPVP("player")
    local isAFK      = UnitIsAFK("player")
    local isDND      = UnitIsDND("player")

    local specName
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local _, sName = GetSpecializationInfo(specIndex, nil, nil, nil, UnitSex("player"))
            specName = sName
        end
    end

    local zone    = GetZoneText and GetZoneText() or nil
    local subzone = GetSubZoneText and GetSubZoneText() or nil
    local loc
    if subzone and subzone ~= "" and subzone ~= zone then
        loc = subzone
    else
        loc = zone
    end

    -- Zeile 1: Name + Status
    local nameLine = name or "Player"
    if isAFK then
        nameLine = nameLine .. " <AFK>"
    elseif isDND then
        nameLine = nameLine .. " <DND>"
    end
    f.name:SetText(nameLine)

    -- Zeile 2: Level + Rasse + Klasse
    local line2 = ""
    if level and level > 0 then
        if race and classLoc then
            line2 = string.format("Level %d %s %s", level, race, classLoc)
        elseif classLoc then
            line2 = string.format("Level %d %s", level, classLoc)
        else
            line2 = string.format("Level %d", level)
        end
    elseif classLoc then
        line2 = classLoc
    end
    f.line2:SetText(line2 or "")

    -- Zeile 3: Spec + Klasse
    local line3 = ""
    if specName and classLoc then
        line3 = string.format("%s %s", specName, classLoc)
    elseif specName then
        line3 = specName
    end
    f.line3:SetText(line3 or "")

    -- Zeile 4: Fraktion + PvP
    local line4 = ""
    if faction or isPVP then
        local text = faction or ""
        if isPVP then
            if text ~= "" then
                text = text .. " – PvP"
            else
                text = "PvP"
            end
        end
        line4 = text
    end
    f.line4:SetText(line4 or "")

    -- Zeile 5: Ort
    f.line5:SetText(loc or "")

        MSUF_PositionPlayerInfoFrame(f)

    f:Show()
end



function MSUF_ShowTargetInfoTooltip()
    local f = MSUF_GetPlayerInfoFrame()
    if not UnitExists("target") then
        f:Hide()
        return
    end

    local name     = UnitName("target")
    local level    = UnitLevel("target")
    local isPlayer = UnitIsPlayer("target")

    local race, classLoc, faction, isPVP, isAFK, isDND
    if isPlayer then
        race     = UnitRace("target")
        classLoc = select(1, UnitClass("target"))
        faction  = UnitFactionGroup("target")
        isPVP    = UnitIsPVP("target")
        isAFK    = UnitIsAFK("target")
        isDND    = UnitIsDND("target")
    end

    local classification = UnitClassification("target")
    local creatureType   = UnitCreatureType("target")

    local zone    = GetZoneText and GetZoneText() or nil
    local subzone = GetSubZoneText and GetSubZoneText() or nil
    local loc
    if subzone and subzone ~= "" and subzone ~= zone then
        loc = subzone
    else
        loc = zone
    end

    -- Zeile 1: Name (+ Status nur für Spieler)
    local nameLine = name or "Target"
    if isPlayer then
        if isAFK then
            nameLine = nameLine .. " <AFK>"
        elseif isDND then
            nameLine = nameLine .. " <DND>"
        end
    end
    f.name:SetText(nameLine)

    -- Zeile 2: Level + Zusatzinfo
    local line2 = ""
    if level and level > 0 then
        if isPlayer then
            if race and classLoc then
                line2 = string.format("Level %d %s %s", level, race, classLoc)
            elseif classLoc then
                line2 = string.format("Level %d %s", level, classLoc)
            else
                line2 = string.format("Level %d", level)
            end
        else
            line2 = string.format("Level %d", level)
            if classification then
                local clsText
                if classification == "elite" then
                    clsText = "Elite"
                elseif classification == "rare" then
                    clsText = "Rare"
                elseif classification == "rareelite" then
                    clsText = "Rare Elite"
                elseif classification == "worldboss" then
                    clsText = "Boss"
                end
                if clsText then
                    line2 = line2 .. string.format(" (%s)", clsText)
                end
            end
        end
    elseif isPlayer and classLoc then
        line2 = classLoc
    end
    f.line2:SetText(line2 or "")

    -- Zeile 3: Spielerklasse oder Kreaturentyp
    local line3 = ""
    if isPlayer then
        line3 = classLoc or ""
    else
        line3 = creatureType or ""
    end
    f.line3:SetText(line3 or "")

    -- Zeile 4: Fraktion/PvP (nur Spieler)
    local line4 = ""
    if isPlayer and (faction or isPVP) then
        local text = faction or ""
        if isPVP then
            if text ~= "" then
                text = text .. " – PvP"
            else
                text = "PvP"
            end
        end
        line4 = text
    end
    f.line4:SetText(line4 or "")

    -- Zeile 5: Ort
    f.line5:SetText(loc or "")

        MSUF_PositionPlayerInfoFrame(f)

    f:Show()
end



function MSUF_ShowFocusInfoTooltip()
    local f = MSUF_GetPlayerInfoFrame()
    if not UnitExists("focus") then
        f:Hide()
        return
    end

    local name     = UnitName("focus")
    local level    = UnitLevel("focus")
    local isPlayer = UnitIsPlayer("focus")

    local race, classLoc, faction, isPVP, isAFK, isDND
    if isPlayer then
        race     = UnitRace("focus")
        classLoc = select(1, UnitClass("focus"))
        faction  = UnitFactionGroup("focus")
        isPVP    = UnitIsPVP("focus")
        isAFK    = UnitIsAFK("focus")
        isDND    = UnitIsDND("focus")
    end

    local classification = UnitClassification("focus")
    local creatureType   = UnitCreatureType("focus")

    local zone    = GetZoneText and GetZoneText() or nil
    local subzone = GetSubZoneText and GetSubZoneText() or nil
    local loc
    if subzone and subzone ~= "" and subzone ~= zone then
        loc = subzone
    else
        loc = zone
    end

    -- Zeile 1: Name (+ Status nur für Spieler)
    local nameLine = name or "Focus"
    if isPlayer then
        if isAFK then
            nameLine = nameLine .. " <AFK>"
        elseif isDND then
            nameLine = nameLine .. " <DND>"
        end
    end
    f.name:SetText(nameLine)

    -- Zeile 2: Level + Zusatzinfo
    local line2 = ""
    if level and level > 0 then
        if isPlayer then
            if race and classLoc then
                line2 = string.format("Level %d %s %s", level, race, classLoc)
            elseif classLoc then
                line2 = string.format("Level %d %s", level, classLoc)
            else
                line2 = string.format("Level %d", level)
            end
        else
            line2 = string.format("Level %d", level)
            if classification then
                local clsText
                if classification == "elite" then
                    clsText = "Elite"
                elseif classification == "rare" then
                    clsText = "Rare"
                elseif classification == "rareelite" then
                    clsText = "Rare Elite"
                elseif classification == "worldboss" then
                    clsText = "Boss"
                end
                if clsText then
                    line2 = line2 .. string.format(" (%s)", clsText)
                end
            end
        end
    elseif isPlayer and classLoc then
        line2 = classLoc
    end
    f.line2:SetText(line2 or "")

    -- Zeile 3: Spielerklasse oder Kreaturentyp
    local line3 = ""
    if isPlayer then
        line3 = classLoc or ""
    else
        line3 = creatureType or ""
    end
    f.line3:SetText(line3 or "")

    -- Zeile 4: Fraktion/PvP (nur Spieler)
    local line4 = ""
    if isPlayer and (faction or isPVP) then
        local text = faction or ""
        if isPVP then
            if text ~= "" then
                text = text .. " – PvP"
            else
                text = "PvP"
            end
        end
        line4 = text
    end
    f.line4:SetText(line4 or "")

    -- Zeile 5: Ort
    f.line5:SetText(loc or "")

        MSUF_PositionPlayerInfoFrame(f)

    f:Show()
end



function MSUF_ShowTargetTargetInfoTooltip()
    local f = MSUF_GetPlayerInfoFrame()
    if not UnitExists("targettarget") then
        f:Hide()
        return
    end

    local name     = UnitName("targettarget")
    local level    = UnitLevel("targettarget")
    local isPlayer = UnitIsPlayer("targettarget")

    local race, classLoc, faction, isPVP, isAFK, isDND
    if isPlayer then
        race     = UnitRace("targettarget")
        classLoc = select(1, UnitClass("targettarget"))
        faction  = UnitFactionGroup("targettarget")
        isPVP    = UnitIsPVP("targettarget")
        isAFK    = UnitIsAFK("targettarget")
        isDND    = UnitIsDND("targettarget")
    end

    local classification = UnitClassification("targettarget")
    local creatureType   = UnitCreatureType("targettarget")

    local zone    = GetZoneText and GetZoneText() or nil
    local subzone = GetSubZoneText and GetSubZoneText() or nil
    local loc
    if subzone and subzone ~= "" and subzone ~= zone then
        loc = subzone
    else
        loc = zone
    end

    -- Zeile 1: Name (+ Status nur für Spieler)
    local nameLine = name or "Target of Target"
    if isPlayer then
        if isAFK then
            nameLine = nameLine .. " <AFK>"
        elseif isDND then
            nameLine = nameLine .. " <DND>"
        end
    end
    f.name:SetText(nameLine)

    -- Zeile 2: Level + Zusatzinfo
    local line2 = ""
    if level and level > 0 then
        if isPlayer then
            if race and classLoc then
                line2 = string.format("Level %d %s %s", level, race, classLoc)
            elseif classLoc then
                line2 = string.format("Level %d %s", level, classLoc)
            else
                line2 = string.format("Level %d", level)
            end
        else
            line2 = string.format("Level %d", level)
            if classification then
                local clsText
                if classification == "elite" then
                    clsText = "Elite"
                elseif classification == "rare" then
                    clsText = "Rare"
                elseif classification == "rareelite" then
                    clsText = "Rare Elite"
                elseif classification == "worldboss" then
                    clsText = "Boss"
                end
                if clsText then
                    line2 = line2 .. string.format(" (%s)", clsText)
                end
            end
        end
    elseif isPlayer and classLoc then
        line2 = classLoc
    end
    f.line2:SetText(line2 or "")

    -- Zeile 3: Spielerklasse oder Kreaturentyp
    local line3 = ""
    if isPlayer then
        line3 = classLoc or ""
    else
        line3 = creatureType or ""
    end
    f.line3:SetText(line3 or "")

    -- Zeile 4: Fraktion/PvP (nur Spieler)
    local line4 = ""
    if isPlayer and (faction or isPVP) then
        local text = faction or ""
        if isPVP then
            if text ~= "" then
                text = text .. " – PvP"
            else
                text = "PvP"
            end
        end
        line4 = text
    end
    f.line4:SetText(line4 or "")

    -- Zeile 5: Ort
    f.line5:SetText(loc or "")

        MSUF_PositionPlayerInfoFrame(f)

    f:Show()
end





function MSUF_ShowBossInfoTooltip(unit)
    local f = MSUF_GetPlayerInfoFrame()
    if not unit or not UnitExists(unit) then
        f:Hide()
        return
    end

    local name     = UnitName(unit)
    local level    = UnitLevel(unit)
    local isPlayer = UnitIsPlayer(unit)

    local race, classLoc, faction, isPVP, isAFK, isDND
    if isPlayer then
        race     = UnitRace(unit)
        classLoc = select(1, UnitClass(unit))
        faction  = UnitFactionGroup(unit)
        isPVP    = UnitIsPVP(unit)
        isAFK    = UnitIsAFK(unit)
        isDND    = UnitIsDND(unit)
    end

    local classification = UnitClassification(unit)
    local creatureType   = UnitCreatureType(unit)

    local zone    = GetZoneText and GetZoneText() or nil
    local subzone = GetSubZoneText and GetSubZoneText() or nil
    local loc
    if subzone and subzone ~= "" and subzone ~= zone then
        loc = subzone
    else
        loc = zone
    end

    -- Zeile 1: Name (+ Status nur für Spieler)
    local nameLine = name or "Boss"
    if isPlayer then
        if isAFK then
            nameLine = nameLine .. " <AFK>"
        elseif isDND then
            nameLine = nameLine .. " <DND>"
        end
    end
    f.name:SetText(nameLine)

    -- Zeile 2: Level + Zusatzinfo
    local line2 = ""
    if level and level > 0 then
        if isPlayer then
            if race and classLoc then
                line2 = string.format("Level %d %s %s", level, race, classLoc)
            elseif classLoc then
                line2 = string.format("Level %d %s", level, classLoc)
            else
                line2 = string.format("Level %d", level)
            end
        else
            line2 = string.format("Level %d", level)
            if classification then
                local clsText
                if classification == "elite" then
                    clsText = "Elite"
                elseif classification == "rare" then
                    clsText = "Rare"
                elseif classification == "rareelite" then
                    clsText = "Rare Elite"
                elseif classification == "worldboss" or classification == "boss" then
                    clsText = "Boss"
                end
                if clsText then
                    line2 = line2 .. string.format(" (%s)", clsText)
                end
            end
        end
    elseif isPlayer and classLoc then
        line2 = classLoc
    end
    f.line2:SetText(line2 or "")

    -- Zeile 3: Spielerklasse oder Kreaturentyp
    local line3 = ""
    if isPlayer then
        line3 = classLoc or ""
    else
        line3 = creatureType or ""
    end
    f.line3:SetText(line3 or "")

    -- Zeile 4: Fraktion/PvP (nur Spieler)
    local line4 = ""
    if isPlayer and (faction or isPVP) then
        local text = faction or ""
        if isPVP then
            if text ~= "" then
                text = text .. " – PvP"
            else
                text = "PvP"
            end
        end
        line4 = text
    end
    f.line4:SetText(line4 or "")

    -- Zeile 5: Ort
    f.line5:SetText(loc or "")

        MSUF_PositionPlayerInfoFrame(f)

    f:Show()
end


function MSUF_ShowPetInfoTooltip()
    local f = MSUF_GetPlayerInfoFrame()
    if not UnitExists("pet") then
        f:Hide()
        return
    end

    local name       = UnitName("pet")
    local level      = UnitLevel("pet")
    local creatureType = UnitCreatureType("pet")

    local zone    = GetZoneText and GetZoneText() or nil
    local subzone = GetSubZoneText and GetSubZoneText() or nil
    local loc
    if subzone and subzone ~= "" and subzone ~= zone then
        loc = subzone
    else
        loc = zone
    end

    -- Zeile 1: Name
    local nameLine = name or "Pet"
    f.name:SetText(nameLine)

    -- Zeile 2: Level
    local line2 = ""
    if level and level > 0 then
        line2 = string.format("Level %d", level)
    end
    f.line2:SetText(line2 or "")

    -- Zeile 3: Kreaturentyp
    local line3 = creatureType or ""
    f.line3:SetText(line3)

    -- Zeile 4: leer (kein PvP/Fraktion für Pet nötig)
    f.line4:SetText("")

    -- Zeile 5: Ort
    f.line5:SetText(loc or "")

        MSUF_PositionPlayerInfoFrame(f)

    f:Show()
end

function MSUF_HidePlayerInfoTooltip()
    if MSUF_PlayerInfoFrame then
        MSUF_PlayerInfoFrame:Hide()
    end
end
-- Kleine Shake-Animation für Castbars bei Interrupts
local function MSUF_EnsureCastbarShakeAnimation(frame)
    if not frame or frame.MSUF_ShakeGroup then
        return
    end

    local group = frame:CreateAnimationGroup("MSUF_ShakeGroup")
    group:SetLooping("NONE")

    -- drei kurze Bewegungen: rechts -> links -> zurück
    local a1 = group:CreateAnimation("Translation")
    a1:SetOffset(4, 0)
    a1:SetDuration(0.05)
    a1:SetOrder(1)

    local a2 = group:CreateAnimation("Translation")
    a2:SetOffset(-8, 0)
    a2:SetDuration(0.10)
    a2:SetOrder(2)

    local a3 = group:CreateAnimation("Translation")
    a3:SetOffset(4, 0)
    a3:SetDuration(0.05)
    a3:SetOrder(3)

    frame.MSUF_ShakeGroup = group
end

-- Globaler Helper: wird von Player- und Target/Focus-Castbars benutzt
function MSUF_PlayCastbarShake(frame)
    if not frame then
        return
    end

    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}

    -- Standard: AN, außer der User hat den Toggle explizit ausgemacht
    if g.castbarInterruptShake == false then
        return
    end

    MSUF_EnsureCastbarShakeAnimation(frame)

    if frame.MSUF_ShakeGroup then
        frame.MSUF_ShakeGroup:Stop()
        frame.MSUF_ShakeGroup:Play()
    end
end
-- CastBar2 integration (custom castbars for player/target/focus)

local function CreateCastBar(name, unit)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetClampedToScreen(true)
    frame.unit = unit
    frame.reverseFill = false -- legacy flag; actual fill controlled via MSUF_GetCastbarReverseFill()

    frame:SetScript("OnEvent", function(self, event, arg1, ...)
        -- Respect global per-unit castbar toggles (player/target/focus).
        -- When a castbar is disabled in the options menu, we completely hide it
        -- and ignore all incoming events so it never appears.
        if not MSUF_IsCastbarEnabledForUnit(self.unit or "") then
            self:SetScript("OnUpdate", nil)
            if self.timeText then
                self.timeText:SetText("")
            end
            if self.latencyBar then
                self.latencyBar:Hide()
            end
            self:Hide()
            return
        end

        if event == "UNIT_SPELLCAST_START" then
            self:Cast()

        elseif event == "UNIT_SPELLCAST_STOP" then
            -- kurzer grüner „Succeeded“-Flash
            self:SetSucceeded()

        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            self:Cast()

        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            -- Channel endet → nur Cast neu auswerten (meistens hide)
            self:Cast()

        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
            -- Flag + Farbe aus den Options
            self.isNotInterruptible = false
            self:UpdateColorForInterruptible()

        elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            -- Flag + Farbe aus den Options
            self.isNotInterruptible = true
            self:UpdateColorForInterruptible()

        elseif event == "UNIT_SPELLCAST_FAILED" then
            -- Cast-Infos sind weg → Cast() versteckt die Bar
            self:Cast()

        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            self:SetInterrupted()

        elseif (event == "PLAYER_TARGET_CHANGED" and self.unit == "target")
            or (event == "PLAYER_FOCUS_CHANGED" and self.unit == "focus")
        then
            if self.timer then
                self.timer:Cancel()
                self.timer = nil
            end
            self.interrupted = nil
            self:Cast()
        end
    end)

    local function CreateCastFrame(self)
        local height = 18
        self:SetHeight(height)
        if (not self:GetWidth()) or self:GetWidth() == 0 then self:SetWidth(250) end

        local background = self:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(self)
        background:SetColorTexture(0, 0, 0, 1)
        self.background = background






        local statusBar = CreateFrame("StatusBar", nil, self)
        statusBar:SetSize(self:GetWidth() - height - 1, self:GetHeight() - 2)
        statusBar:SetPoint("LEFT", self, "LEFT", height + 1, 0)

        -- Use the same SharedMedia-based castbar texture as the player bar
        local texture = MSUF_GetCastbarTexture and MSUF_GetCastbarTexture() or "Interface\\TargetingFrame\\UI-StatusBar"
        statusBar:SetStatusBarTexture(texture)
        statusBar:GetStatusBarTexture():SetHorizTile(true)
        statusBar:SetReverseFill(MSUF_GetCastbarReverseFill(false))
        self.statusBar = statusBar


        local icon = statusBar:CreateTexture(nil, "OVERLAY", nil, 7)
        icon:SetSize(height, height)
        icon:SetPoint("LEFT", self, "LEFT", 0, 0)
        self.icon = icon

        local backgroundBar = statusBar:CreateTexture(nil, "BACKGROUND")
        backgroundBar:SetAllPoints(statusBar)
        backgroundBar:SetTexture(texture)
        backgroundBar:SetVertexColor(0.176, 0.176, 0.176, 1)
        self.backgroundBar = backgroundBar

        local castText = statusBar:CreateFontString(nil, "OVERLAY")
        castText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        castText:SetPoint("LEFT", statusBar, "LEFT", 2, 0)
        self.castText = castText
        -- Zeittext rechts auf der Player-Castbar
        local timeText = statusBar:CreateFontString(nil, "OVERLAY")
        timeText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        timeText:SetPoint("RIGHT", statusBar, "RIGHT", -2, 0)
        timeText:SetText("")
        self.timeText = timeText
    end

       
        -- Central Castbar Manager: one OnUpdate for all MSUF castbars
        if not MSUF_CastbarManager then
            MSUF_CastbarManager = CreateFrame("Frame")
            MSUF_CastbarManager.active = {}
            MSUF_CastbarManager.elapsed = 0

            local function MSUF_CastbarManager_OnUpdate(self, elapsed)
                -- Global throttling via MSUF_CastbarUpdateInterval (seconds)
                local interval = MSUF_CastbarUpdateInterval or 0.02
                elapsed = elapsed or 0
                self.elapsed = (self.elapsed or 0) + elapsed
                if self.elapsed < interval then
                    return
                end
                local dt = self.elapsed
                self.elapsed = 0

                local active = self.active
                if not active then
                    return
                end

                for frame in pairs(active) do
                    if frame and frame.statusBar and frame:IsShown() and MSUF_UpdateCastbarFrame then
                        MSUF_UpdateCastbarFrame(frame, dt)
                    else
                        active[frame] = nil
                    end
                end

                if not next(active) then
                    self:Hide()
                end
            end

            MSUF_CastbarManager:SetScript("OnUpdate", MSUF_CastbarManager_OnUpdate)
            MSUF_CastbarManager:Hide()

            function MSUF_RegisterCastbar(frame)
                if not frame then return end
                if not MSUF_CastbarManager.active then
                    MSUF_CastbarManager.active = {}
                end
                MSUF_CastbarManager.active[frame] = true
                MSUF_CastbarManager:Show()
            end

            function MSUF_UnregisterCastbar(frame)
                if not frame or not MSUF_CastbarManager.active then
                    return
                end
                MSUF_CastbarManager.active[frame] = nil
                if not next(MSUF_CastbarManager.active) then
                    MSUF_CastbarManager:Hide()
                end
            end

            function MSUF_UpdateCastbarFrame(frame, dt)
                if not frame or not frame.statusBar then
                    return
                end

                -- Original-Animation weiterlaufen lassen
                frame.statusBar:SetValue(GetTime() * 1000)

                -- Eigene Sekunden-Anzeige nur mit elapsed + castDuration
                if frame.timeText and frame.castDuration and frame.castDuration > 0 then
                    frame.castElapsed = (frame.castElapsed or 0) + (dt or 0)

                    if frame.castElapsed < 0 then
                        frame.castElapsed = 0
                    elseif frame.castElapsed > frame.castDuration then
                        frame.castElapsed = frame.castDuration
                    end

                    local remaining = frame.castDuration - frame.castElapsed
                    if remaining < 0 then
                        remaining = 0
                    end
                    frame.timeText:SetFormattedText("%.1f", remaining)
                elseif frame.timeText then
                    -- keine saubere Dauer → Text leer
                    frame.timeText:SetText("")
                end
            end
        end

function frame:Cast()
        local spellName, text, texture, startTime, endTime, _, _, notInterruptible, _ = UnitCastingInfo(self.unit)
        local isChanneled = false
        if type(spellName) == "nil" then
            spellName, text, texture, startTime, endTime, _, notInterruptible, _ = UnitChannelInfo(self.unit)
            isChanneled = true
        end

        -- NEU: laufenden Hide-Timer abbrechen (Back-to-back / latency gaps)
        if self.hideTimer and self.hideTimer.Cancel then
            self.hideTimer:Cancel()
            self.hideTimer = nil
        end

        if type(startTime) ~= "nil" then
            -- PATCH A: laufenden Hide-Timer abbrechen (Back-to-back / latency gaps)
            if self.hideTimer and self.hideTimer.Cancel then
                self.hideTimer:Cancel()
                self.hideTimer = nil
            end

            self.interrupted = nil

            if self.icon and texture then
                self.icon:SetTexture(texture)
            end
            if self.castText then
                self.castText:SetText(text or spellName or "")
            end

            ------------------------------------------------
            -- Castdauer nur über GetSpellInfo(spellName)
            -- → keine secret-Werte, kein spellID nötig
            ------------------------------------------------
            self.castDuration = nil
            self.castElapsed  = nil

            if spellName and GetSpellInfo then
                local _, _, _, baseCastTimeMS = GetSpellInfo(spellName)
                if baseCastTimeMS and baseCastTimeMS > 0 then
                    self.castDuration = baseCastTimeMS / 1000
                    self.castElapsed  = 0
                end
            end

            -- Balken-Animation wie bisher über startTime/endTime
            if startTime and endTime then
                self.statusBar:SetMinMaxValues(startTime, endTime)
            end
            self.statusBar:SetReverseFill(MSUF_GetCastbarReverseFill(isChanneled))

            if MSUF_RegisterCastbar then
                MSUF_RegisterCastbar(self)
            end


            -- Initialer Tick
            self.statusBar:SetValue(GetTime() * 1000)
            if self.timeText then
                if self.castDuration and self.castDuration > 0 then
                    self.timeText:SetFormattedText("%.1f", self.castDuration)
                else
                    self.timeText:SetText("")
                end
            end

            -- Interrupt-Farbe nur noch über Nameplate-BarType bestimmen
            self:UpdateColorForInterruptible()
            self:Show()
        else
            -- PATCH B: Grace-Period gegen Spellqueue/Latency-Lücken
            if self.hideTimer and self.hideTimer.Cancel then
                self.hideTimer:Cancel()
            end

            self.hideTimer = C_Timer.NewTimer(0.12, function()
                if not self or not self.unit then return end

                local castName = UnitCastingInfo(self.unit)
                local chanName = UnitChannelInfo(self.unit)

                -- Falls inzwischen doch ein Cast/Channel da ist: neu aufbauen statt hiden
                if castName or chanName then
                    self:Cast()
                    return
                end

                self:SetScript("OnUpdate", nil)
                if self.timeText then
                    self.timeText:SetText("")
                end
                if not self.interrupted then
                    self:Hide()
                end
            end)
        end
    end

    function frame:UpdateColorForInterruptible()
        if not self or not self.statusBar then
            return
        end

        local g = MSUF_DB and MSUF_DB.general
        if not g then
            return
        end

        -- dieselben Keys wie bei der Player-Castbar / im Castbar-Menü
        local interruptibleKey    = g.castbarInterruptibleColor    or "turquoise"
        local nonInterruptibleKey = g.castbarNonInterruptibleColor or "red"

        local isNonInterruptible = false
        local unit = self.unit

        -- sichere Abfrage über Nameplate.barType (Midnight-Way)
        if C_NamePlate and C_NamePlate.GetNamePlateForUnit and unit then
            local nameplate = C_NamePlate.GetNamePlateForUnit(unit, issecure())
            if nameplate then
                local bar = (nameplate.UnitFrame and nameplate.UnitFrame.castBar)
                    or nameplate.castBar
                    or nameplate.CastBar

                local barType = bar and bar.barType
                if barType == "uninterruptable"
                    or barType == "uninterruptible"
                    or barType == "uninterruptibleSpell"
                    or barType == "shield"
                then
                    isNonInterruptible = true
                end
            end
        end

        -- Flag aus den UNIT_SPELLCAST_(NOT_)INTERRUPTIBLE-Events
        if self.isNotInterruptible then
            isNonInterruptible = true
        end

        -- Farbe aus dem Color-Dropdown holen
        local color
        if MSUF_GetColorFromKey then
            local key = isNonInterruptible and nonInterruptibleKey or interruptibleKey
            color = MSUF_GetColorFromKey(key)
        end

        -- Fallback-Farben, falls irgendwas schiefgeht
        if not color then
            if isNonInterruptible then
                color = CreateColor(0.4, 0.01, 0.01, 1)   -- rot
            else
                color = CreateColor(0, 1, 0.9, 1)         -- dein Türkis
            end
        end

        local r, g, b, a = color:GetRGBA()
        self.statusBar:SetStatusBarColor(r, g, b, a)
    end



    function frame:SetInterrupted()
        self:SetScript("OnUpdate", nil)
        self.interrupted = true
        self.statusBar:SetStatusBarColor(1, 0, 0, 1)
        self.castText:SetText("Interrupted")

        -- NEU: Shake-Feedback bei Interrupt
        if MSUF_PlayCastbarShake then
            MSUF_PlayCastbarShake(self)
        end

        if self.timer then
            self.timer:Cancel()
            self.timer = nil
        end

        self.timer = C_Timer.After(0.8, function()
            if self.interrupted then
                self.interrupted = nil
                self:Hide()
            end
        end)
    end

    function frame:SetSucceeded()
        self:SetScript("OnUpdate", nil)
        if self.interrupted then return end
        self.statusBar:SetStatusBarColor(0.8, 0.1, 0.1, 1)

        self.timer = C_Timer.After(0.8, function()
            self:Hide()
        end)
    end

    frame:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)

    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)

    frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unit)

    frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)

    if unit == "target" or unit == "focus" then
        frame:RegisterEvent("PLAYER_" .. unit:upper() .. "_CHANGED")
    end

    local msufFrame = _G["MSUF_" .. unit]
    if msufFrame then
        frame:ClearAllPoints()
        if unit == "target" then
            frame:SetPoint("BOTTOMLEFT", msufFrame, "TOPLEFT", 0, 5)
        elseif unit == "focus" then
            frame:SetPoint("TOPLEFT", msufFrame, "BOTTOMLEFT", 0, -5)
        elseif unit == "player" then
            -- Player castbar: standardmäßig direkt über dem MSUF-Playerframe
            frame:SetPoint("BOTTOM", msufFrame, "TOP", 0, 5)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, -300)
        end

        local w = msufFrame:GetWidth()
        if w and w > 0 then
            frame:SetWidth(w)
        end
    end

    CreateCastFrame(frame)
    frame:Hide()

    -- Compatibility aliases so existing MSUF code (textures, visuals) can still find these bars
    if unit == "target" then
        MSUF_TargetCastbar = frame
    elseif unit == "focus" then
        MSUF_FocusCastbar = frame
    elseif unit == "player" then
        MSUF_PlayerCastbar = frame
    end

    return frame
end

-- Safe player castbar backend (MSUF custom bar)
------------------------------------------------------
MSUF_PlayerCastbar = MSUF_PlayerCastbar or nil -- forward declaration (shared global)
-- Liefert die effektive Grace-Periode in Sekunden
-- Basis: Slider-Wert (g.castbarGraceMs) + dynamische Anpassung an den Ping
local function MSUF_GetCastbarGraceSeconds()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}

    -- Basis aus dem Slider (0–400 ms)
    local baseMs = tonumber(g.castbarGraceMs) or 120
    if baseMs < 0   then baseMs = 0   end
    if baseMs > 400 then baseMs = 400 end

    -- Dynamische Komponente: 2x höchste Latenz (Home/World)
    local _, _, homeMS, worldMS = GetNetStats()
    local latencyMS = math.max(homeMS or 0, worldMS or 0)
    local dynamicMs = (latencyMS or 0) * 2

    local graceMs = math.max(baseMs, dynamicMs)

    -- Harte Obergrenze, damit es nicht lächerlich lang wird
    if graceMs > 400 then
        graceMs = 400
    end

    return graceMs / 1000
end

local function MSUF_PlayerCastbar_UpdateColorForInterruptible(self)
    if not self or not self.statusBar then
        return
    end

    local g = MSUF_DB and MSUF_DB.general or {}

    local interruptibleKey    = g.castbarInterruptibleColor    or "turquoise"
    local nonInterruptibleKey = g.castbarNonInterruptibleColor or "red"

    local isNonInterruptible = false

    -- Player nameplate (if available)
    local unit = self.unit or "player"
    local nameplate = C_NamePlate
        and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit(unit, issecure())

    if nameplate then
        local bar = (nameplate.UnitFrame and nameplate.UnitFrame.castBar)
            or nameplate.castBar
            or nameplate.CastBar

        local barType = bar and bar.barType
        if barType == "uninterruptable"
            or barType == "uninterruptible"
            or barType == "uninterruptibleSpell"
        then
            isNonInterruptible = true
        end
    end

    if self.isNotInterruptible then
        isNonInterruptible = true
    end

    local color

    if MSUF_GetColorFromKey then
        local key = isNonInterruptible and nonInterruptibleKey or interruptibleKey
        color = MSUF_GetColorFromKey(key)
    end

    if not color then
        if isNonInterruptible then
            color = CreateColor(0.4, 0.01, 0.01, 1)
        else
            color = CreateColor(0, 1, 0.9, 1)
        end
    end

    local r, g, b, a = color:GetRGBA()
    self.statusBar:SetStatusBarColor(r, g, b, a)
end
local function MSUF_GetInterruptFeedbackColor()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}
    local key = g.castbarInterruptColor or "red"

    if MSUF_GetColorFromKey then
        local color = MSUF_GetColorFromKey(key)
        if color then
            return color:GetRGBA()
        end
    end

    -- Fallback, falls irgendwas schief geht
    return 0.8, 0.1, 0.1, 1
end
-- Wie lange der "Interrupt Feedback"-Effekt sichtbar bleibt
local MSUF_PLAYER_INTERRUPT_FEEDBACK_DURATION = 0.7

-- Timer-Callback für das "Interrupt Feedback" der Player-Castbar
local function MSUF_PlayerCastbar_HideIfNoLongerCasting(timer)
    -- Frame an den Timer hängen (siehe ShowInterruptFeedback)
    local self = timer and timer.msuCastbarFrame
    if not self or not self.unit then
        return
    end

    local castName = UnitCastingInfo(self.unit)
    local chanName = UnitChannelInfo(self.unit)

    -- Wenn wieder ein Cast aktiv ist, normaler Cast-Flow
    if castName or chanName then
        if MSUF_PlayerCastbar_Cast then
            MSUF_PlayerCastbar_Cast(self)
        end
        return
    end

    -- Wenn nichts mehr gecastet wird: Bar ausblenden
    self:SetScript("OnUpdate", nil)
    if self.timeText then
        self.timeText:SetText("")
    end
    self:Hide()
end

local function MSUF_PlayerCastbar_ShowInterruptFeedback(self, label)
    if not self or not self.statusBar then
        return
    end

    -- alten Timer abbrechen, falls vorhanden
    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end

    -- laufende OnUpdate-Logik stoppen
    self:SetScript("OnUpdate", nil)

    self.interruptFeedbackEndTime = GetTime() + MSUF_PLAYER_INTERRUPT_FEEDBACK_DURATION

    -- Bar vorbereiten
    self.statusBar:SetMinMaxValues(0, 1)
    self.statusBar:SetValue(0.8)
    self.statusBar:SetReverseFill(false)

    -- rot einfärben für "unterbrochen"
    self.statusBar:SetStatusBarColor(0.8, 0.1, 0.1, 1)

    if self.castText then
        self.castText:SetText(label or INTERRUPTED)
    end

    self:Show()
    self:SetAlpha(1)

    -- Gnadenfrist (Grace) über Helper + Ping + Slider
    local grace = MSUF_GetCastbarGraceSeconds()

    -- Timer erstellen, Frame am Timer referenzieren (keine Upvalues nötig)
    self.hideTimer = C_Timer.NewTimer(grace, MSUF_PlayerCastbar_HideIfNoLongerCasting)
    self.hideTimer.msuCastbarFrame = self
end

local function MSUF_PlayerCastbar_EmpowerStart(self, spellID)
    if not self or not self.statusBar then
        return
    end

    -- Flag: aktuell läuft ein Empower-Cast
    self.isEmpower = true
    self.interruptFeedbackEndTime = nil
     if self.latencyBar then self.latencyBar:Hide() end

    -- Name + Icon über die ganz normale Player-Cast-API holen
    local name, text, texture = UnitCastingInfo("player")
    if not name then
        name, text, texture = UnitChannelInfo("player")
    end

    if self.icon and texture then
        self.icon:SetTexture(texture)
    end
    if self.castText then
        self.castText:SetText(name or "")
    end

    -- Simple, sichere Annahme für max. Haltezeit (z.B. 3.0s)
    -- -> kein GetUnitEmpowerHoldAtMaxTime, also keine Secret-APIs
    local maxHold = 3.0
    self.empowerStartTime = GetTime()
    self.empowerMaxHold   = maxHold

    self.statusBar:SetMinMaxValues(0, maxHold)
    self.statusBar:SetReverseFill(false)

    -- Empower-Stufe-Ticks entlang der Leiste verteilen
    local stageTicks = self.empowerStageTicks
    if stageTicks and self.statusBar then
        local numStages = #stageTicks + 1        -- z.B. 3 Ticks = 4 Stufen
        local barWidth = self.statusBar:GetWidth() or 0

        if barWidth > 0 and numStages > 1 then
            for i, tick in ipairs(stageTicks) do
                local fraction = i / numStages   -- 1/4, 2/4, 3/4 ...
                local offsetX = barWidth * fraction

                tick:ClearAllPoints()
                tick:SetPoint("CENTER", self.statusBar, "LEFT", offsetX, 0)
                tick:Show()
            end
        else
            -- falls aus irgendeinem Grund keine Breite: lieber verstecken
            for _, tick in ipairs(stageTicks) do
                tick:Hide()
            end
        end
    end

    self:SetScript("OnUpdate", function(frame)
        if not frame or not frame.statusBar then
            return
        end

        local now = GetTime()
        local elapsed = now - (frame.empowerStartTime or now)
        if elapsed < 0 then
            elapsed = 0
        end

        local maxHoldLocal = frame.empowerMaxHold or maxHold
        if elapsed > maxHoldLocal then
            elapsed = maxHoldLocal
        end

        frame.statusBar:SetValue(elapsed)

        if frame.timeText then
            frame.timeText:SetFormattedText("%.1f s", elapsed)
        end
    end)

    MSUF_PlayerCastbar_UpdateColorForInterruptible(self)
    self:Show()
end
local function MSUF_PlayerCastbar_Cast(self)
    if not self or not self.unit or not self.statusBar then
        return
    end

    local name, text, texture, startTime, endTime = UnitCastingInfo(self.unit)
    local isChanneled = false

    if not name then
        name, text, texture, startTime, endTime = UnitChannelInfo(self.unit)
        isChanneled = true
    end

    if startTime and endTime then
        -- NEU: laufenden Hide-Timer abbrechen, sonst hidet er Back-to-Back-Channels
        if self.hideTimer and self.hideTimer.Cancel then
            self.hideTimer:Cancel()
            self.hideTimer = nil
        end

        self.castStartTime = startTime
        self.castEndTime   = endTime
        self.isChanneled   = isChanneled

        if self.icon and texture then
            self.icon:SetTexture(texture)
        end

        if self.castText then
            self.castText:SetText(text or "")
        end

        self.statusBar:SetMinMaxValues(startTime, endTime)
        self.statusBar:SetReverseFill(MSUF_GetCastbarReverseFill(isChanneled))
                -- NEU: Lag-Tolerance Zone updaten
        if self.latencyBar then
            local _, _, homeMS, worldMS = GetNetStats()
            local latencyMS = math.max(homeMS or 0, worldMS or 0)

            local queueMS = tonumber(GetCVar("SpellQueueWindow") or "0") or 0
            local tolMS = math.max(latencyMS, queueMS)

            local durationMS = (endTime - startTime)
            local pct = 0
            if durationMS and durationMS > 0 then
                pct = tolMS / durationMS
            end
            if pct > 1 then pct = 1 end
            if pct < 0 then pct = 0 end

            local barW = self.statusBar:GetWidth() or 0
            local w = barW * pct
            if w < 1 then w = 1 end

            self.latencyBar:ClearAllPoints()
            self.latencyBar:SetPoint("TOPRIGHT", self.statusBar, "TOPRIGHT", 0, 0)
            self.latencyBar:SetPoint("BOTTOMRIGHT", self.statusBar, "BOTTOMRIGHT", 0, 0)
            self.latencyBar:SetWidth(w)
            self.latencyBar:Show()
        end

        self:SetScript("OnUpdate", function(frame, elapsed)
            if not frame or not frame.statusBar then return end

            local interval = MSUF_CastbarUpdateInterval or 0.02
            elapsed = elapsed or 0
            frame._playerCastbarUpdateAccum = (frame._playerCastbarUpdateAccum or 0) + elapsed
            if frame._playerCastbarUpdateAccum < interval then
                return
            end
            frame._playerCastbarUpdateAccum = 0

            local nowMs = GetTime() * 1000
            frame.statusBar:SetValue(nowMs)

            if frame.timeText and frame.castEndTime then
                local remaining = (frame.castEndTime - nowMs) / 1000
                if remaining < 0 then remaining = 0 end
                frame.timeText:SetFormattedText("%.1f s", remaining)
            end
        end)

        local nowMs = GetTime() * 1000
        self.statusBar:SetValue(nowMs)
        if self.timeText and self.castEndTime then
            local remaining = (self.castEndTime - nowMs) / 1000
            if remaining < 0 then remaining = 0 end
            self.timeText:SetFormattedText("%.1f s", remaining)
        end

        MSUF_PlayerCastbar_UpdateColorForInterruptible(self)
        self:Show()
        return
    end

      -- Grace-Period gegen Spellqueue/Latency-Lücken (instant -> channel / channel -> channel)
    if self.hideTimer and self.hideTimer.Cancel then
        self.hideTimer:Cancel()
    end

    local grace = MSUF_GetCastbarGraceSeconds()

    self.hideTimer = C_Timer.NewTimer(grace, function()
        if not self or not self.unit then return end

        local castName = UnitCastingInfo(self.unit)
        local chanName = UnitChannelInfo(self.unit)

        if castName or chanName then
            MSUF_PlayerCastbar_Cast(self)
            return
        end

        self:SetScript("OnUpdate", nil)
        if self.timeText then
            self.timeText:SetText("")
        end
        self:Hide()
    end)
end

local function MSUF_PlayerCastbar_OnEvent(self, event, ...)
    -- Respect global toggle: if the MSUF player castbar is disabled in the options,
    -- we completely hide it and ignore all incoming events.
    if not MSUF_IsCastbarEnabledForUnit("player") then
        self:SetScript("OnUpdate", nil)
        self.interruptFeedbackEndTime = nil
        if self.timeText then
            self.timeText:SetText("")
        end
        if self.latencyBar then
            self.latencyBar:Hide()
        end
        self:Hide()
        return
    end

        -- FAILED: nur hiden, wenn wirklich nichts (neues) castet/channeled
    if event == "UNIT_SPELLCAST_FAILED" then
        local castNow = UnitCastingInfo("player")
        local chanNow = UnitChannelInfo("player")
        if castNow or chanNow then
            -- altes FAILED kam zu spät -> ignorieren
            return
        end

        self:SetScript("OnUpdate", nil)
        self.interruptFeedbackEndTime = nil
        self:Hide()
        return
    end

    -- INTERRUPTED: nur Feedback zeigen, wenn gerade kein neuer Cast/Channel läuft
    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        local castNow = UnitCastingInfo("player")
        local chanNow = UnitChannelInfo("player")
        if castNow or chanNow then
            -- Interrupt vom alten Channel -> ignorieren
            return
        end

        MSUF_PlayerCastbar_ShowInterruptFeedback(self, INTERRUPTED)
        return
    end

    -- Evoker Empower: Haltephase anzeigen
    if event == "UNIT_SPELLCAST_EMPOWER_START" then
        local unitTarget, castGUID, spellID = ...
        if unitTarget ~= "player" then return end
        MSUF_PlayerCastbar_EmpowerStart(self, spellID)
        return

    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        if self.isEmpower then
            self.isEmpower = nil
            self.empowerStartTime = nil
            self.empowerMaxHold = nil

            if self.empowerStageTicks then
                for _, tick in ipairs(self.empowerStageTicks) do
                    tick:Hide()
                end
            end

            self:SetScript("OnUpdate", nil)
            if self.timeText then
                self.timeText:SetText("")
            end
                        if self.latencyBar then self.latencyBar:Hide() end

            self:Hide()
        end
        return
    end

    -- Cast/Channel Refresh
    if event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_DELAYED"
        or event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "PLAYER_ENTERING_WORLD"
    then
        C_Timer.After(0, function()
            if not self or not self.unit then return end

            local castName = UnitCastingInfo(self.unit)
            local chanName = UnitChannelInfo(self.unit)

            -- SUCCEEDED/DELAYED/CHANNEL_UPDATE dürfen NICHT hide-triggern,
            -- wenn grad noch nix Neues läuft.
            if castName or chanName
                or event == "UNIT_SPELLCAST_START"
                or event == "UNIT_SPELLCAST_STOP"
                or event == "UNIT_SPELLCAST_CHANNEL_START"
                or event == "UNIT_SPELLCAST_CHANNEL_STOP"
            then
                MSUF_PlayerCastbar_Cast(self)
            else
                -- NEU: Bei CHANNEL_START einmal kurz nachziehen,
                -- falls UnitChannelInfo im ersten Frame noch nil ist.
                if event == "UNIT_SPELLCAST_CHANNEL_START" then
                    C_Timer.After(0.02, function()
                        if not self or not self.unit then return end
                        local cn = UnitCastingInfo(self.unit)
                        local ch = UnitChannelInfo(self.unit)
                        if cn or ch then
                            MSUF_PlayerCastbar_Cast(self)
                        end
                    end)
                end
            end

        end)
        return
    end

    -- Interruptible-Färbung live updaten
    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        self.isNotInterruptible = false
        MSUF_PlayerCastbar_UpdateColorForInterruptible(self)
        return

    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        self.isNotInterruptible = true
        MSUF_PlayerCastbar_UpdateColorForInterruptible(self)
        return
    end
end

function MSUF_InitSafePlayerCastbar()
    -- Create the custom castbar frame once
    if not MSUF_PlayerCastbar then
        local frame = CreateFrame("Frame", "MSUF_PlayerCastBar", UIParent)
        frame:SetClampedToScreen(true)
        MSUF_PlayerCastbar = frame
        frame.unit = "player"

        -- Basic visuals (kannst du später noch stylen)
        local height = 18
        frame:SetSize(200, height) -- Breite wird in Reanchor gesetzt

        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(frame)
        background:SetColorTexture(0, 0, 0, 1)
        frame.background = background

        local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        icon:SetSize(height, height)
        icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.icon = icon

        local statusBar = CreateFrame("StatusBar", nil, frame)
        statusBar:SetPoint("LEFT", icon, "RIGHT", 0, 0)
        statusBar:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        statusBar:SetHeight(height - 2)

        local texture = MSUF_GetCastbarTexture()
        statusBar:SetStatusBarTexture(texture)
        statusBar:GetStatusBarTexture():SetHorizTile(true)
        frame.statusBar = statusBar

        local backgroundBar = frame:CreateTexture(nil, "ARTWORK")
        backgroundBar:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
        backgroundBar:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        backgroundBar:SetTexture(texture)
        backgroundBar:SetVertexColor(0.176, 0.176, 0.176, 1)
        frame.backgroundBar = backgroundBar

               -- Spellname links auf der Leiste
        local castText = statusBar:CreateFontString(nil, "OVERLAY")
        local fontPath, fontSize, fontFlags = GameFontHighlight:GetFont()
        castText:SetFont(fontPath, fontSize, fontFlags)
        castText:SetPoint("LEFT", statusBar, "LEFT", 2, 0)
        frame.castText = castText

        -- NEU: Zeit rechts auf der Player-Castbar (z.B. "1.2 s")
        EnsureDB()
        local g = MSUF_DB.general
        local timeX = g.castbarPlayerTimeOffsetX or -2
        local timeY = g.castbarPlayerTimeOffsetY or 0

        local timeText = statusBar:CreateFontString(nil, "OVERLAY")
        local latencyBar = statusBar:CreateTexture(nil, "OVERLAY")
        latencyBar:SetColorTexture(1, 0, 0, 0.25) -- rot, halbtransparent
        latencyBar:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
        latencyBar:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        latencyBar:SetWidth(0)
        latencyBar:Hide()
        frame.latencyBar = latencyBar
        timeText:SetFont(fontPath, fontSize, fontFlags)
        timeText:SetPoint("RIGHT", statusBar, "RIGHT", timeX, timeY)
        timeText:SetJustifyH("RIGHT")
        timeText:SetText("")
        frame.timeText = timeText
        -- Empower-Stufe-Ticks (Evoker) – werden nur bei Empower benutzt
        frame.empowerStageTicks = frame.empowerStageTicks or {}
        local numStages = 3      -- oder 4, je nach Taste; wir machen es erst mal generisch
        local barHeight = height -- height ist oben in der Funktion definiert

        for i = 1, numStages - 1 do
            local tick = frame.empowerStageTicks[i]
            if not tick then
                tick = statusBar:CreateTexture(nil, "OVERLAY")
                tick:SetColorTexture(1, 1, 1, 0.8) -- dünne helle Linie
                frame.empowerStageTicks[i] = tick
            end

            tick:SetSize(2, barHeight)  -- 2 px breit, volle Höhe
            tick:Hide()                 -- Standard: versteckt, nur bei Empower sichtbar
        end

        -- Evoker Empower (nur Player)
        frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP",  "player")
        -- UPDATE brauchen wir vorerst nicht

        -- Events für player
                frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")

        frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")

        frame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

        frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")

        frame:RegisterEvent("PLAYER_ENTERING_WORLD")


        frame:SetScript("OnEvent", MSUF_PlayerCastbar_OnEvent)
        frame:Hide()
    end
        -- NEU: falls beim Init schon ein Cast/Channel läuft (z.B. beim Zonen/Reload),
        -- Bar sofort aufbauen statt bis zum nächsten Event zu warten.
        C_Timer.After(0, function()
            if not MSUF_PlayerCastbar or not MSUF_PlayerCastbar_Cast then return end
            local castName = UnitCastingInfo("player")
            local chanName = UnitChannelInfo("player")
            if castName or chanName then
                MSUF_PlayerCastbar_Cast(MSUF_PlayerCastbar)
            end
        end)

    -- Anchor/resize to current MSUF player frame
    local msufPlayer = UnitFrames and UnitFrames["player"]
    if not msufPlayer or not MSUF_PlayerCastbar then
        return
    end

    local g = MSUF_DB and MSUF_DB.general
    local offsetX = g and g.castbarPlayerOffsetX or 0
    local offsetY = g and g.castbarPlayerOffsetY or 5

    MSUF_PlayerCastbar:ClearAllPoints()
    MSUF_PlayerCastbar:SetPoint("BOTTOMLEFT", msufPlayer, "TOPLEFT", offsetX, offsetY)

    local width = msufPlayer:GetWidth()
    if width and width > 0 then
        MSUF_PlayerCastbar:SetWidth(width)
    end
end


-- Driver für Castbar-Initialisierung & Blizzard-Castbar-Hiding
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")

driver:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Eigene Target-/Focus-Castbars erzeugen, falls noch nicht vorhanden
        if not _G["TargetCastBar"] then
            CreateCastBar("TargetCastBar", "target")
        end
        if not _G["FocusCastBar"] then
            CreateCastBar("FocusCastBar", "focus")
        end

        -- Gespeicherte Positionen / Größen / Texturen anwenden
        if MSUF_ReanchorTargetCastBar then MSUF_ReanchorTargetCastBar() end
        if MSUF_ReanchorFocusCastBar  then MSUF_ReanchorFocusCastBar()  end
        if MSUF_ReanchorPlayerCastBar then MSUF_ReanchorPlayerCastBar() end
        if MSUF_UpdateCastbarVisuals  then MSUF_UpdateCastbarVisuals()  end
        if MSUF_UpdateCastbarTextures then MSUF_UpdateCastbarTextures() end

        -- Dieses Event nur einmal brauchen
        self:UnregisterEvent("PLAYER_LOGIN")

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Default Target-Castbar deaktivieren
        if TargetFrameSpellBar then
            TargetFrameSpellBar:UnregisterAllEvents()
            TargetFrameSpellBar:Hide()
            TargetFrameSpellBar:HookScript("OnShow", function(bar)
                bar:Hide()
            end)
        end

        -- Default Focus-Castbar deaktivieren
        if FocusFrameSpellBar then
            FocusFrameSpellBar:UnregisterAllEvents()
            FocusFrameSpellBar:Hide()
            FocusFrameSpellBar:HookScript("OnShow", function(bar)
                bar:Hide()
            end)
        end

        -- Default Pet-Castbar deaktivieren (Player behalten wir als Fallback)
        if PetCastingBarFrame then
            PetCastingBarFrame:UnregisterAllEvents()
            PetCastingBarFrame:Hide()
            PetCastingBarFrame:HookScript("OnShow", function(bar)
                bar:Hide()
            end)
        end

        -- Auch dieses Event nur einmal brauchen
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)
------------------------------------------------------
-- MSUF castbar reanchor wrappers (CastBar2-based)
------------------------------------------------------

------------------------------------------------------
-- Reanchor Blizzard target frame under MSUF target (for default target castbar attachment)
------------------------------------------------------
function MSUF_AttachBlizzardTargetFrame()
    if not TargetFrame then
        return
    end

    local msufTarget = UnitFrames and UnitFrames["target"]
    if not msufTarget then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    TargetFrame:ClearAllPoints()

    local g = MSUF_DB and MSUF_DB.general
    local offsetX = g and g.castbarTargetOffsetX or 65
    local offsetY = g and g.castbarTargetOffsetY or -15

    TargetFrame:SetPoint("CENTER", msufTarget, "CENTER", offsetX, offsetY)
end

function MSUF_ReanchorTargetCastBar()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}
    local frame = MSUF_TargetCastbar or _G["TargetCastBar"]
    if not frame then return end

    -- If the target castbar toggle is disabled, completely hide the bar
    -- and stop any animation. This prevents it from showing up at all.
    if g.enableTargetCastbar == false then
        frame:SetScript("OnUpdate", nil)
        if frame.timeText then
            frame.timeText:SetText("")
        end
        if frame.latencyBar then
            frame.latencyBar:Hide()
        end
        frame:Hide()
        if MSUF_TargetCastbarPreview then
            MSUF_TargetCastbarPreview:Hide()
        end
        return
    end

    local msufTarget = UnitFrames and UnitFrames["target"]
    if not msufTarget then return end

    local offsetX = g.castbarTargetOffsetX or 65
    local offsetY = g.castbarTargetOffsetY or -15

    -- Position: attach to the MSUF target frame
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", msufTarget, "TOPLEFT", offsetX, offsetY)

    -- Width: match the MSUF target frame
    local width = msufTarget:GetWidth()
    if width and width > 0 then
        local height = frame:GetHeight() or 18
        frame:SetWidth(width)

        if frame.statusBar then
            frame.statusBar:SetWidth(width - height - 1)
        end
    end

    -- Optional preview bar: keep it in sync position-wise
    if MSUF_TargetCastbarPreview and MSUF_PositionTargetCastbarPreview then
        MSUF_PositionTargetCastbarPreview()
    end
end
function MSUF_ReanchorFocusCastBar()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}
    local frame = MSUF_FocusCastbar or _G["FocusCastBar"]
    if not frame then return end

    -- If the focus castbar toggle is disabled, completely hide the bar
    -- and stop any animation. This prevents it from showing up at all.
    if g.enableFocusCastbar == false then
        frame:SetScript("OnUpdate", nil)
        if frame.timeText then
            frame.timeText:SetText("")
        end
        if frame.latencyBar then
            frame.latencyBar:Hide()
        end
        frame:Hide()
        if MSUF_FocusCastbarPreview then
            MSUF_FocusCastbarPreview:Hide()
        end
        return
    end

    local msufFocus = UnitFrames and UnitFrames["focus"]
    if not msufFocus then return end

    local offsetX = g.castbarFocusOffsetX or (g.castbarTargetOffsetX or 65)
    local offsetY = g.castbarFocusOffsetY or (g.castbarTargetOffsetY or -15)

    -- Position: attach to the MSUF focus frame
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", msufFocus, "TOPLEFT", offsetX, offsetY)

    -- Width: match the MSUF focus frame
    local width = msufFocus:GetWidth()
    if width and width > 0 then
        local height = frame:GetHeight() or 18
        frame:SetWidth(width)

        if frame.statusBar then
            frame.statusBar:SetWidth(width - height - 1)
        end
    end

    -- Preview mit umpositionieren
    if MSUF_FocusCastbarPreview and MSUF_PositionFocusCastbarPreview then
        MSUF_PositionFocusCastbarPreview()
    end
end

local function MSUF_HideBlizzardPlayerCastbar()
    local frames = {}

    if PlayerCastingBarFrame then
        table.insert(frames, PlayerCastingBarFrame)
    end

    -- Some UIs / versions still use CastingBarFrame separately
    if CastingBarFrame and CastingBarFrame ~= PlayerCastingBarFrame then
        table.insert(frames, CastingBarFrame)
    end

    if #frames == 0 then
        return
    end

    for _, frame in ipairs(frames) do
        if frame and not frame.MSUF_HideHooked then
            frame.MSUF_HideHooked = true

            -- Securely hook Show: when Blizzard tries to show the bar,
            -- always hide it again. Player castbars are fully managed by MSUF.
            hooksecurefunc(frame, "Show", function(self)
                self:Hide()
            end)
        end

        frame:Hide()
    end
end
function MSUF_ReanchorPlayerCastBar()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}

    -- Ensure Blizzard player castbar is always hidden; MSUF fully manages visibility.
    MSUF_HideBlizzardPlayerCastbar()

    -- Toggle: when disabled, completely hide the MSUF player castbar as well.
    if g.enablePlayerCastbar == false then
        if MSUF_PlayerCastbar then
            MSUF_PlayerCastbar:SetScript("OnUpdate", nil)
            MSUF_PlayerCastbar.interruptFeedbackEndTime = nil
            if MSUF_PlayerCastbar.timeText then
                MSUF_PlayerCastbar.timeText:SetText("")
            end
            if MSUF_PlayerCastbar.latencyBar then
                MSUF_PlayerCastbar.latencyBar:Hide()
            end
            MSUF_PlayerCastbar:Hide()
        end
        if MSUF_PlayerCastbarPreview then
            MSUF_PlayerCastbarPreview:Hide()
        end
        if PlayerCastingBarFrame then
            PlayerCastingBarFrame:Show()
        end
        return
    end

    -- We use our own bar; hide the Blizzard one, but keep events intact.
    if PlayerCastingBarFrame then
        PlayerCastingBarFrame:Hide()
    end
    if CastingBarFrame and CastingBarFrame ~= PlayerCastingBarFrame then
        CastingBarFrame:Hide()
    end

    -- Initialize our own bar and anchor it directly to the MSUF player frame
    MSUF_InitSafePlayerCastbar()

    local msufPlayer = UnitFrames and UnitFrames["player"]
    if not msufPlayer or not MSUF_PlayerCastbar then
        return
    end

    local offsetX = g.castbarPlayerOffsetX or 0
    local offsetY = g.castbarPlayerOffsetY or 5

    MSUF_PlayerCastbar:ClearAllPoints()
    MSUF_PlayerCastbar:SetPoint("BOTTOM", msufPlayer, "TOP", offsetX, offsetY)

    local width = msufPlayer:GetWidth()
    if width and width > 0 then
        local height = MSUF_PlayerCastbar:GetHeight() or 18
        MSUF_PlayerCastbar:SetWidth(width)
        if MSUF_PlayerCastbar.statusBar then
            MSUF_PlayerCastbar.statusBar:SetWidth(width - height - 1)
        end
    end

    -- Cast time text position aus der DB anwenden
    if MSUF_PlayerCastbar.timeText and MSUF_PlayerCastbar.statusBar then
        local timeX = g.castbarPlayerTimeOffsetX or -2
        local timeY = g.castbarPlayerTimeOffsetY or 0
        MSUF_PlayerCastbar.timeText:ClearAllPoints()
        MSUF_PlayerCastbar.timeText:SetPoint(
            "RIGHT",
            MSUF_PlayerCastbar.statusBar,
            "RIGHT",
            timeX,
            timeY
        )
    end

    -- Optional preview bar: keep it in sync position-wise
    if MSUF_PlayerCastbarPreview and MSUF_PositionPlayerCastbarPreview then
        MSUF_PositionPlayerCastbarPreview()
    end
end

-- ############################################################
-- Player, Target & Focus Castbar Preview (fake bars for positioning)
-- ############################################################

MSUF_PlayerCastbarPreview  = MSUF_PlayerCastbarPreview  or nil
MSUF_TargetCastbarPreview  = MSUF_TargetCastbarPreview  or nil
MSUF_FocusCastbarPreview   = MSUF_FocusCastbarPreview   or nil


local function MSUF_CreateCastbarEditArrows(frame, unit)
    if not frame or frame.MSUF_CastbarArrowsCreated then
        return
    end
    frame.MSUF_CastbarArrowsCreated = true

    local arrowSize = 18

    -- Shared nudge logic: either move (offset) or resize (width/height)
    local function Nudge(moveDX, moveDY, sizeDW, sizeDH)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general

        local prefix
        if unit == "player" then
            prefix = "castbarPlayer"
        elseif unit == "target" then
            prefix = "castbarTarget"
        elseif unit == "focus" then
            prefix = "castbarFocus"
        else
            return
        end

        local offXKey = prefix .. "OffsetX"
        local offYKey = prefix .. "OffsetY"
        local barWKey = prefix .. "BarWidth"
        local barHKey = prefix .. "BarHeight"

        if MSUF_EditModeSizing then
            -- SIZE MODE: width/height
            local baseW = g[barWKey] or g.castbarGlobalWidth  or frame:GetWidth()  or 250
            local baseH = g[barHKey] or g.castbarGlobalHeight or frame:GetHeight() or 18

            baseW = math.max(50, baseW + (sizeDW or 0))
            baseH = math.max(8,  baseH + (sizeDH or 0))

            g[barWKey] = math.floor(baseW + 0.5)
            g[barHKey] = math.floor(baseH + 0.5)

            if MSUF_UpdateCastbarVisuals then
                MSUF_UpdateCastbarVisuals()
            end
        else
            -- POSITION MODE: x/y offsets
            local defaultX, defaultY
            if unit == "player" then
                defaultX, defaultY = 0, 5
            else
                defaultX, defaultY = 65, -15
            end

            g[offXKey] = (g[offXKey] or defaultX) + (moveDX or 0)
            g[offYKey] = (g[offYKey] or defaultY) + (moveDY or 0)

            if unit == "player" and MSUF_ReanchorPlayerCastBar then
                MSUF_ReanchorPlayerCastBar()
            elseif unit == "target" and MSUF_ReanchorTargetCastBar then
                MSUF_ReanchorTargetCastBar()
            elseif unit == "focus" and MSUF_ReanchorFocusCastBar then
                MSUF_ReanchorFocusCastBar()
            end
        end

        if MSUF_UpdateCastbarEditInfo then
            MSUF_UpdateCastbarEditInfo(unit)
        end
    end

    local function CreateArrowButton(name, direction, point, relPoint, ofsX, ofsY, onClick, tooltipText)
        local btn = CreateFrame("Button", name, frame)
        btn:SetSize(arrowSize, arrowSize)

        -- clean white square, same style as unitframe arrows
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        btn._bg = bg

        local symbols = {
            LEFT  = "<",
            RIGHT = ">",
            UP    = "^",
            DOWN  = "v",
        }

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetText(symbols[direction] or "")
        label:SetTextColor(0, 0, 0, 1)
        btn._label = label

        btn:SetPoint(point, frame, relPoint or point, ofsX, ofsY)

        btn:SetScript("OnEnter", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
            if tooltipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)
            end
        end)

        btn:SetScript("OnLeave", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
            GameTooltip:Hide()
        end)

        btn:SetScript("OnMouseDown", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)

        btn:SetScript("OnMouseUp", function(self)
            if self._bg then
                self._bg:SetColorTexture(1, 1, 1, 1)
            end
        end)

        if onClick then
            btn:SetScript("OnClick", onClick)
        end

        return btn
    end

    -- UP
    frame.MSUF_CastbarArrowUp = CreateArrowButton(
        frame:GetName() .. "ArrowUp",
        "UP",
        "BOTTOM", "TOP",
        0, 2,
        function()
            if MSUF_EditModeSizing then
                Nudge(0, 0, 0, -1)  -- height smaller
            else
                Nudge(0, 1, 0, 0)   -- move up
            end
        end,
        "Position: move up\nSize mode: decrease height"
    )

    -- DOWN
    frame.MSUF_CastbarArrowDown = CreateArrowButton(
        frame:GetName() .. "ArrowDown",
        "DOWN",
        "TOP", "BOTTOM",
        0, -2,
        function()
            if MSUF_EditModeSizing then
                Nudge(0, 0, 0, 1)   -- height bigger
            else
                Nudge(0, -1, 0, 0)  -- move down
            end
        end,
        "Position: move down\nSize mode: increase height"
    )

    -- LEFT
    frame.MSUF_CastbarArrowLeft = CreateArrowButton(
        frame:GetName() .. "ArrowLeft",
        "LEFT",
        "RIGHT", "LEFT",
        -2, 0,
        function()
            if MSUF_EditModeSizing then
                Nudge(0, 0, -1, 0)  -- width smaller
            else
                Nudge(-1, 0, 0, 0)  -- move left
            end
        end,
        "Position: move left\nSize mode: decrease width"
    )

    -- RIGHT
    frame.MSUF_CastbarArrowRight = CreateArrowButton(
        frame:GetName() .. "ArrowRight",
        "RIGHT",
        "LEFT", "RIGHT",
        2, 0,
        function()
            if MSUF_EditModeSizing then
                Nudge(0, 0, 1, 0)   -- width bigger
            else
                Nudge(1, 0, 0, 0)   -- move right
            end
        end,
        "Position: move right\nSize mode: increase width"
    )
end


local function MSUF_CreatePlayerCastbarPreview()
    if MSUF_PlayerCastbarPreview then
        return MSUF_PlayerCastbarPreview
    end

    local frame = CreateFrame("Frame", "MSUF_PlayerCastbarPreview", UIParent, "BackdropTemplate")
    frame:SetClampedToScreen(true)
    MSUF_PlayerCastbarPreview = frame

    frame:SetFrameStrata("DIALOG")
    frame:SetSize(250, 18)

    -- simple dark background so the bar is visible everywhere
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.8)
    frame.backgroundBar = bg

    -- status bar
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
    statusBar:SetSize(250, 16)
    local tex = MSUF_GetCastbarTexture and MSUF_GetCastbarTexture() or "Interface\\TargetingFrame\\UI-StatusBar"
    statusBar:SetStatusBarTexture(tex)
    statusBar:GetStatusBarTexture():SetHorizTile(true)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0.5)
    frame.statusBar = statusBar

    -- icon
    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    icon:SetTexture(136235) -- generic spell icon
    frame.icon = icon

    -- spell name text
    local castText = statusBar:CreateFontString(nil, "OVERLAY")
    local fontPath, fontSize, flags = GameFontHighlight:GetFont()
    castText:SetFont(fontPath, fontSize, flags)
    castText:SetJustifyH("LEFT")
    castText:SetPoint("LEFT", statusBar, "LEFT", 2, 0)
    castText:SetText("Player castbar preview")
    frame.castText = castText

    -- Edit-Mode arrows for this preview
    MSUF_CreateCastbarEditArrows(frame, "player")

    -- drag logic: adjust DB offsets based on cursor delta
    frame:EnableMouse(true)

     frame:SetScript("OnMouseDown", function(self, button)
        -- Rechtsklick: Popup öffnen (nur im Positionsmodus)
        if button == "RightButton" then
            if not MSUF_UnitEditModeActive then return end
            if MSUF_EditModeSizing then return end -- Popup nur im Position-Mode
            if InCombatLockdown and InCombatLockdown() then return end

            if MSUF_OpenCastbarPositionPopup then
                MSUF_OpenCastbarPositionPopup("player", self)
            end
            return
        end

        -- Linksklick: Drag wie bisher
        if button ~= "LeftButton" then return end
        if InCombatLockdown and InCombatLockdown() then return end

        EnsureDB()
        local g = MSUF_DB.general or {}
        if not g.castbarPlayerPreviewEnabled then return end

        self.isDragging = true

        local uiScale = UIParent:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        cx, cy = cx / uiScale, cy / uiScale

        self.dragStartCursorX = cx
        self.dragStartCursorY = cy

        if MSUF_EditModeSizing then
            local baseW = g.castbarPlayerBarWidth  or g.castbarGlobalWidth  or self:GetWidth()  or 250
            local baseH = g.castbarPlayerBarHeight or g.castbarGlobalHeight or self:GetHeight() or 18
            self.dragStartWidth  = baseW
            self.dragStartHeight = baseH
            self.dragMode = "SIZE"
        else
            self.dragStartOffsetX = g.castbarPlayerOffsetX or 0
            self.dragStartOffsetY = g.castbarPlayerOffsetY or 5
            self.dragMode = "MOVE"
        end

        self:SetScript("OnUpdate", function(self, elapsed)
            if not self.isDragging then
                self:SetScript("OnUpdate", nil)
                return
            end

            local uiScale = UIParent:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            cx, cy = cx / uiScale, cy / uiScale

            local dx = cx - (self.dragStartCursorX or cx)
            local dy = cy - (self.dragStartCursorY or cy)

            EnsureDB()
            local g2 = MSUF_DB.general or {}

            if self.dragMode == "SIZE" then
                local newW = math.max(50, (self.dragStartWidth  or 250) + dx)
                local newH = math.max(8,  (self.dragStartHeight or 18) + dy)

                g2.castbarPlayerBarWidth  = math.floor(newW + 0.5)
                g2.castbarPlayerBarHeight = math.floor(newH + 0.5)

                if MSUF_UpdateCastbarVisuals then
                    MSUF_UpdateCastbarVisuals()
                end
            else
                g2.castbarPlayerOffsetX = (self.dragStartOffsetX or 0) + dx
                g2.castbarPlayerOffsetY = (self.dragStartOffsetY or 5) + dy

                if MSUF_ReanchorPlayerCastBar then
                    MSUF_ReanchorPlayerCastBar()
                end
            end

            if MSUF_UpdateCastbarEditInfo then
                MSUF_UpdateCastbarEditInfo("player")
            end
            if MSUF_SyncCastbarPositionPopup then
                MSUF_SyncCastbarPositionPopup("player")
            end
        end)
    end)


    frame:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if self.isDragging then
            self.isDragging = false
        end
    end)

    return frame
end

local function MSUF_CreateTargetCastbarPreview()
    if MSUF_TargetCastbarPreview then
        return MSUF_TargetCastbarPreview
    end

    local frame = CreateFrame("Frame", "MSUF_TargetCastbarPreview", UIParent, "BackdropTemplate")
    frame:SetClampedToScreen(true)
    MSUF_TargetCastbarPreview = frame

    frame:SetFrameStrata("DIALOG")
    frame:SetSize(250, 18)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.8)
    frame.backgroundBar = bg

    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
    statusBar:SetSize(250, 16)
    local tex = MSUF_GetCastbarTexture and MSUF_GetCastbarTexture() or "Interface\\TargetingFrame\\UI-StatusBar"
    statusBar:SetStatusBarTexture(tex)
    statusBar:GetStatusBarTexture():SetHorizTile(true)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0.5)
    frame.statusBar = statusBar

    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    icon:SetTexture(136235)
    frame.icon = icon

    local castText = statusBar:CreateFontString(nil, "OVERLAY")
    local fontPath, fontSize, flags = GameFontHighlight:GetFont()
    castText:SetFont(fontPath, fontSize, flags)
    castText:SetJustifyH("LEFT")
    castText:SetPoint("LEFT", statusBar, "LEFT", 2, 0)
    castText:SetText("Target castbar preview")
    frame.castText = castText

    -- Edit-Mode arrows for this preview
    MSUF_CreateCastbarEditArrows(frame, "target")

    frame:EnableMouse(true)

      frame:SetScript("OnMouseDown", function(self, button)
        -- Rechtsklick: Popup öffnen (nur im Positionsmodus)
        if button == "RightButton" then
            if not MSUF_UnitEditModeActive then return end
            if MSUF_EditModeSizing then return end
            if InCombatLockdown and InCombatLockdown() then return end

            if MSUF_OpenCastbarPositionPopup then
                MSUF_OpenCastbarPositionPopup("target", self)
            end
            return
        end

        -- Linksklick: Drag wie bisher
        if button ~= "LeftButton" then return end
        if InCombatLockdown and InCombatLockdown() then return end

        EnsureDB()
        local g = MSUF_DB.general or {}
        if not g.castbarPlayerPreviewEnabled then return end

        self.isDragging = true

        local uiScale = UIParent:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        cx, cy = cx / uiScale, cy / uiScale

        self.dragStartCursorX = cx
        self.dragStartCursorY = cy

        if MSUF_EditModeSizing then
            local baseW = g.castbarTargetBarWidth  or g.castbarGlobalWidth  or self:GetWidth()  or 250
            local baseH = g.castbarTargetBarHeight or g.castbarGlobalHeight or self:GetHeight() or 18
            self.dragStartWidth  = baseW
            self.dragStartHeight = baseH
            self.dragMode = "SIZE"
        else
            self.dragStartOffsetX = g.castbarTargetOffsetX or 65
            self.dragStartOffsetY = g.castbarTargetOffsetY or -15
            self.dragMode = "MOVE"
        end

        self:SetScript("OnUpdate", function(self, elapsed)
            if not self.isDragging then
                self:SetScript("OnUpdate", nil)
                return
            end

            local uiScale = UIParent:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            cx, cy = cx / uiScale, cy / uiScale

            local dx = cx - (self.dragStartCursorX or cx)
            local dy = cy - (self.dragStartCursorY or cy)

            EnsureDB()
            local g2 = MSUF_DB.general or {}

            if self.dragMode == "SIZE" then
                local newW = math.max(50, (self.dragStartWidth  or 250) + dx)
                local newH = math.max(8,  (self.dragStartHeight or 18) + dy)

                g2.castbarTargetBarWidth  = math.floor(newW + 0.5)
                g2.castbarTargetBarHeight = math.floor(newH + 0.5)

                if MSUF_UpdateCastbarVisuals then
                    MSUF_UpdateCastbarVisuals()
                end
            else
                local baseX = self.dragStartOffsetX or g2.castbarTargetOffsetX or 65
                local baseY = self.dragStartOffsetY or g2.castbarTargetOffsetY or -15

                g2.castbarTargetOffsetX = baseX + dx
                g2.castbarTargetOffsetY = baseY + dy

                if MSUF_ReanchorTargetCastBar then
                    MSUF_ReanchorTargetCastBar()
                end
            end

            if MSUF_UpdateCastbarEditInfo then
                MSUF_UpdateCastbarEditInfo("target")
            end
            if MSUF_SyncCastbarPositionPopup then
                MSUF_SyncCastbarPositionPopup("target")
            end
        end)
    end)


    frame:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if self.isDragging then
            self.isDragging = false
        end
    end)

    return frame
end
local function MSUF_CreateFocusCastbarPreview()
    if MSUF_FocusCastbarPreview then
        return MSUF_FocusCastbarPreview
    end

    local frame = CreateFrame("Frame", "MSUF_FocusCastbarPreview", UIParent, "BackdropTemplate")
    frame:SetClampedToScreen(true)
    MSUF_FocusCastbarPreview = frame

    frame:SetFrameStrata("DIALOG")
    frame:SetSize(250, 18)

    -- Hintergrund
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.8)
    frame.backgroundBar = bg

    -- Statusbar
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
    statusBar:SetSize(250, 16)
    local tex = MSUF_GetCastbarTexture and MSUF_GetCastbarTexture() or "Interface\\TargetingFrame\\UI-StatusBar"
    statusBar:SetStatusBarTexture(tex)
    statusBar:GetStatusBarTexture():SetHorizTile(true)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0.5)
    frame.statusBar = statusBar

    -- Icon
    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    icon:SetTexture(136235)
    frame.icon = icon

    -- Text
    local castText = statusBar:CreateFontString(nil, "OVERLAY")
    local fontPath, fontSize, flags = GameFontHighlight:GetFont()
    castText:SetFont(fontPath, fontSize, flags)
    castText:SetJustifyH("LEFT")
    castText:SetPoint("LEFT", statusBar, "LEFT", 2, 0)
    castText:SetText("Focus castbar preview")
    frame.castText = castText

    -- Edit-Mode arrows for this preview
    MSUF_CreateCastbarEditArrows(frame, "focus")

    --------------------------------------------------
    -- Drag mit der Maus (wie Target/Player)
    --------------------------------------------------
    frame:EnableMouse(true)

      frame:SetScript("OnMouseDown", function(self, button)
        -- Rechtsklick: Popup öffnen (nur im Positionsmodus)
        if button == "RightButton" then
            if not MSUF_UnitEditModeActive then return end
            if MSUF_EditModeSizing then return end
            if InCombatLockdown and InCombatLockdown() then return end

            if MSUF_OpenCastbarPositionPopup then
                MSUF_OpenCastbarPositionPopup("focus", self)
            end
            return
        end

        -- Linksklick: Drag wie bisher
        if button ~= "LeftButton" then return end
        if InCombatLockdown and InCombatLockdown() then return end

        EnsureDB()
        local g = MSUF_DB.general or {}
        if not g.castbarPlayerPreviewEnabled then return end

        self.isDragging = true

        local uiScale = UIParent:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        cx, cy = cx / uiScale, cy / uiScale

        self.dragStartCursorX = cx
        self.dragStartCursorY = cy

        if MSUF_EditModeSizing then
            local baseW = g.castbarFocusBarWidth  or g.castbarGlobalWidth  or self:GetWidth()  or 250
            local baseH = g.castbarFocusBarHeight or g.castbarGlobalHeight or self:GetHeight() or 18
            self.dragStartWidth  = baseW
            self.dragStartHeight = baseH
            self.dragMode = "SIZE"
        else
            self.dragStartOffsetX = g.castbarFocusOffsetX or g.castbarTargetOffsetX or 65
            self.dragStartOffsetY = g.castbarFocusOffsetY or g.castbarTargetOffsetY or -15
            self.dragMode = "MOVE"
        end

        self:SetScript("OnUpdate", function(self, elapsed)
            if not self.isDragging then
                self:SetScript("OnUpdate", nil)
                return
            end

            local uiScale = UIParent:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            cx, cy = cx / uiScale, cy / uiScale

            local dx = cx - (self.dragStartCursorX or cx)
            local dy = cy - (self.dragStartCursorY or cy)

            EnsureDB()
            local g2 = MSUF_DB.general or {}

            if self.dragMode == "SIZE" then
                local newW = math.max(50, (self.dragStartWidth  or 250) + dx)
                local newH = math.max(8,  (self.dragStartHeight or 18) + dy)

                g2.castbarFocusBarWidth  = math.floor(newW + 0.5)
                g2.castbarFocusBarHeight = math.floor(newH + 0.5)

                if MSUF_UpdateCastbarVisuals then
                    MSUF_UpdateCastbarVisuals()
                end
            else
                local baseX = self.dragStartOffsetX or g2.castbarTargetOffsetX or 65
                local baseY = self.dragStartOffsetY or g2.castbarTargetOffsetY or -15

                g2.castbarFocusOffsetX = baseX + dx
                g2.castbarFocusOffsetY = baseY + dy

                if MSUF_ReanchorFocusCastBar then
                    MSUF_ReanchorFocusCastBar()
                end
            end

            if MSUF_UpdateCastbarEditInfo then
                MSUF_UpdateCastbarEditInfo("focus")
            end
            if MSUF_SyncCastbarPositionPopup then
                MSUF_SyncCastbarPositionPopup("focus")
            end
        end)
    end)


    frame:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if self.isDragging then
            self.isDragging = false
        end
    end)

    return frame
end

function MSUF_PositionPlayerCastbarPreview()
    if not MSUF_PlayerCastbarPreview then
        return
    end

    EnsureDB()
    local g = MSUF_DB.general or {}

    local offsetX = g.castbarPlayerOffsetX or 0
    local offsetY = g.castbarPlayerOffsetY or 5

    local anchorFrame
    if g.castbarPlayerDetached then
        anchorFrame = MSUF_GetAnchorFrame()
    else
        if not UnitFrames or not UnitFrames["player"] then
            return
        end
        anchorFrame = UnitFrames["player"]
    end

    if not anchorFrame then
        return
    end

    MSUF_PlayerCastbarPreview:ClearAllPoints()
    MSUF_PlayerCastbarPreview:SetPoint("BOTTOM", anchorFrame, "TOP", offsetX, offsetY)
end


function MSUF_PositionTargetCastbarPreview()
    if not MSUF_TargetCastbarPreview then
        return
    end

    EnsureDB()
    local g = MSUF_DB.general or {}

    local offsetX = g.castbarTargetOffsetX or 65
    local offsetY = g.castbarTargetOffsetY or -15

    local anchorFrame
    if g.castbarTargetDetached then
        anchorFrame = MSUF_GetAnchorFrame()
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
    MSUF_TargetCastbarPreview:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", offsetX, offsetY)
end
function MSUF_PositionFocusCastbarPreview()
    if not MSUF_FocusCastbarPreview then
        return
    end

    EnsureDB()
    local g = MSUF_DB.general or {}

    local offsetX = g.castbarFocusOffsetX or (g.castbarTargetOffsetX or 65)
    local offsetY = g.castbarFocusOffsetY or (g.castbarTargetOffsetY or -15)

    local anchorFrame
    if g.castbarFocusDetached then
        anchorFrame = MSUF_GetAnchorFrame()
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
    MSUF_FocusCastbarPreview:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", offsetX, offsetY)
end

function MSUF_UpdatePlayerCastbarPreview()
    EnsureDB()
    local g = MSUF_DB.general or {}

    -- Toggle off: hide all preview bars
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
        return
    end

    -- Player preview
    local playerPreview = MSUF_PlayerCastbarPreview or MSUF_CreatePlayerCastbarPreview()
    if playerPreview and MSUF_PositionPlayerCastbarPreview then
        MSUF_PositionPlayerCastbarPreview()
        playerPreview:Show()
    end

    -- Target preview (only if target frame exists)
    if UnitFrames and UnitFrames["target"] then
        local targetPreview = MSUF_TargetCastbarPreview or MSUF_CreateTargetCastbarPreview()
        if targetPreview and MSUF_PositionTargetCastbarPreview then
            MSUF_PositionTargetCastbarPreview()
            targetPreview:Show()
        end
    elseif MSUF_TargetCastbarPreview then
        MSUF_TargetCastbarPreview:Hide()
    end

    -- Focus preview (only if focus frame exists)
    if UnitFrames and UnitFrames["focus"] then
        local focusPreview = MSUF_FocusCastbarPreview or MSUF_CreateFocusCastbarPreview()
        if focusPreview and MSUF_PositionFocusCastbarPreview then
            MSUF_PositionFocusCastbarPreview()
            focusPreview:Show()
        end
    elseif MSUF_FocusCastbarPreview then
        MSUF_FocusCastbarPreview:Hide()
    end

    -- let the global castbar visual helpers style the previews as well
    if MSUF_UpdateCastbarVisuals then
        MSUF_UpdateCastbarVisuals()
    end
    if MSUF_UpdateCastbarTextures then
        MSUF_UpdateCastbarTextures()
    end
end






---------------------------------------------------------------------
-- Player/Frame tab layout: clean two-column grouping with more space
---------------------------------------------------------------------
local function MSUF_RelayoutPlayerFrameOptions()
    -- Grab existing widgets created in the options constructor
    local widthSlider        = _G["MSUF_WidthSlider"]
    local heightSlider       = _G["MSUF_HeightSlider"]

    local showNameCB         = _G["MSUF_ShowNameCheck"]
    local showHPCB           = _G["MSUF_ShowHPCheck"]
    local showPowerCB        = _G["MSUF_ShowPowerCheck"]
    local enableFrameCB      = _G["MSUF_EnableFrameCheck"]
    local bossTestCB         = _G["MSUF_BossTestModeCheck"]

    local nameOffsetXSlider  = _G["MSUF_NameOffsetXSlider"]
    local nameOffsetYSlider  = _G["MSUF_NameOffsetYSlider"]
    local hpOffsetXSlider    = _G["MSUF_HPOffsetXSlider"]
    local hpOffsetYSlider    = _G["MSUF_HPOffsetYSlider"]
    local powerOffsetXSlider = _G["MSUF_PowerOffsetXSlider"]
    local powerOffsetYSlider = _G["MSUF_PowerOffsetYSlider"]

    local anchorCheck        = _G["MSUF_AnchorToCooldownCheck"]

    -- Bail out if options haven't been created yet
    if not widthSlider or not heightSlider or not nameOffsetXSlider then
        return
    end

    local frameGroup = widthSlider:GetParent()
    if not frameGroup or frameGroup.MSUF_PlayerLayoutDone then
        return
    end
    frameGroup.MSUF_PlayerLayoutDone = true

    ------------------------------------------------------------
    -- Small helpers: section titles + separators
    ------------------------------------------------------------
    local function CreateSectionTitle(parent, text, x, y)
        local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        fs:SetText(text)
        return fs
    end

    local function CreateSeparator(parent, x, y, width)
        local tex = parent:CreateTexture(nil, "ARTWORK")
        tex:SetColorTexture(1, 1, 1, 0.14)
        tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        tex:SetSize(width, 1)
        return tex
    end

    -- Column anchors (tuned so there is plenty of room and no overlap)
    local leftX  = 40
    local rightX = 380

    -- Title row: both section titles share the same Y so they align
    local titleY = -130
    CreateSectionTitle(frameGroup, "Frame size & visibility", leftX,  titleY)
    CreateSectionTitle(frameGroup, "Text offsets",            rightX, titleY)
    CreateSeparator   (frameGroup, leftX,                     titleY - 18, 560)

    ------------------------------------------------------------
    -- LEFT COLUMN: size + basic toggles
    ------------------------------------------------------------
if showNameCB then
    showNameCB:ClearAllPoints()
    showNameCB:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", leftX, titleY - 50)
end

if showHPCB then
    showHPCB:ClearAllPoints()
    showHPCB:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", leftX, titleY - 85)
end

if showPowerCB then
    showPowerCB:ClearAllPoints()
    showPowerCB:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", leftX, titleY - 120)
end

if enableFrameCB then
    enableFrameCB:ClearAllPoints()
    enableFrameCB:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", leftX, titleY - 155)
end

-- Anchor-Checkbox direkt darunter
if anchorCheck then
    anchorCheck:ClearAllPoints()
    anchorCheck:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", leftX, titleY - 190)
end

    -- Optional: preview boss frames toggle under the anchor checkbox
    if bossTestCB then
        bossTestCB:ClearAllPoints()
        bossTestCB:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", leftX, titleY - 345)
    end

    ------------------------------------------------------------
    -- RIGHT COLUMN: all text offsets with extra spacing
    -- Base Y is tied to the section title so "Name offset X"
    -- sits clearly underneath "Text offsets".
    ------------------------------------------------------------
    local baseRightY = titleY - 50   -- first row a bit lower than header
    local stepY      = 70            -- vertical spacing between rows

    if nameOffsetXSlider then
        nameOffsetXSlider:ClearAllPoints()
        nameOffsetXSlider:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", rightX, baseRightY)
    end

    if nameOffsetYSlider then
        nameOffsetYSlider:ClearAllPoints()
        nameOffsetYSlider:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", rightX, baseRightY - stepY)
    end

    if hpOffsetXSlider then
        hpOffsetXSlider:ClearAllPoints()
        hpOffsetXSlider:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", rightX, baseRightY - stepY * 2)
    end

    if hpOffsetYSlider then
        hpOffsetYSlider:ClearAllPoints()
        hpOffsetYSlider:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", rightX, baseRightY - stepY * 3)
    end

    if powerOffsetXSlider then
        powerOffsetXSlider:ClearAllPoints()
        powerOffsetXSlider:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", rightX, baseRightY - stepY * 4)
    end

    if powerOffsetYSlider then
        powerOffsetYSlider:ClearAllPoints()
        powerOffsetYSlider:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", rightX, baseRightY - stepY * 5)
    end
end

-- Run after login once the options panel exists
local msufPlayerLayoutFrame = CreateFrame("Frame")
msufPlayerLayoutFrame:RegisterEvent("PLAYER_LOGIN")
msufPlayerLayoutFrame:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.7, MSUF_RelayoutPlayerFrameOptions)
    else
        MSUF_RelayoutPlayerFrameOptions()
    end
end)



---------------------------------------------------------------------
-- Bars tab layout: two-column grouping similar to Player frame tab
---------------------------------------------------------------------
local function MSUF_FindLabelByText(parent, text)
    if not parent or not text then return nil end
    local regions = { parent:GetRegions() }
    for _, region in ipairs(regions) do
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            if region.GetText and region:GetText() == text then
                return region
            end
        end
    end
    return nil
end

local function MSUF_RelayoutBarsOptions()
    local barModeDrop        = _G["MSUF_BarModeDropdown"]
    local darkToneDrop       = _G["MSUF_DarkToneDropdown"]
    local darkBgSlider       = _G["MSUF_DarkBgBrightnessSlider"]
    local barTextureDrop     = _G["MSUF_BarTextureDropdown"]
    local gradientCheck      = _G["MSUF_GradientEnableCheck"]
    local gradientSlider     = _G["MSUF_GradientStrengthSlider"]
    local borderCheck        = _G["MSUF_UseBarBorderCheck"]
    local borderDrop         = _G["MSUF_BorderStyleDropdown"]

    local targetPowerCheck   = _G["MSUF_TargetPowerBarCheck"]
    local bossPowerCheck     = _G["MSUF_BossPowerBarCheck"]
    local playerPowerCheck   = _G["MSUF_PlayerPowerBarCheck"]
    local focusPowerCheck    = _G["MSUF_FocusPowerBarCheck"]
    local powerBarHeightEdit = _G["MSUF_PowerBarHeightEdit"]
    local hpTextModeDrop     = _G["MSUF_HPTextModeDropdown"]

    if not barModeDrop then
        return
    end

    local barGroup = barModeDrop:GetParent()
    if not barGroup or barGroup.MSUF_BarsLayoutDone then
        return
    end
    barGroup.MSUF_BarsLayoutDone = true

    ------------------------------------------------------------
    -- Helpers: section titles + separators
    ------------------------------------------------------------
    local function CreateSectionTitle(parent, text, x, y)
        local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        fs:SetText(text)
        return fs
    end

    local function CreateSeparator(parent, x, y, width)
        local tex = parent:CreateTexture(nil, "ARTWORK")
        tex:SetColorTexture(1, 1, 1, 0.14)
        tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        tex:SetSize(width, 1)
        return tex
    end

    local leftX  = 40
    local rightX = 380
    local titleY = -130

    -- Hide the old big "Bar appearance" title if present
    local oldTitle = MSUF_FindLabelByText(barGroup, "Bar appearance")
    if oldTitle then
        oldTitle:Hide()
    end

    local leftTitle  = CreateSectionTitle(barGroup, "Bar appearance",       leftX,  titleY)
    local rightTitle = CreateSectionTitle(barGroup, "Power bars & HP text", rightX, titleY)
    CreateSeparator(barGroup, leftX, titleY - 18, 560)

    ------------------------------------------------------------
    -- LEFT COLUMN: visual style
    ------------------------------------------------------------
    -- Bar mode dropdown + label
    barModeDrop:ClearAllPoints()
    barModeDrop:SetPoint("TOPLEFT", barGroup, "TOPLEFT", leftX - 16, -180)

    local barModeLabel = MSUF_FindLabelByText(barGroup, "Bar mode")
    if barModeLabel then
        barModeLabel:ClearAllPoints()
        barModeLabel:SetPoint("BOTTOMLEFT", barModeDrop, "TOPLEFT", 16, 4)
    end

    -- Dark mode color dropdown sits below bar mode
    if darkToneDrop then
        darkToneDrop:ClearAllPoints()
        darkToneDrop:SetPoint("TOPLEFT", barModeDrop, "BOTTOMLEFT", 0, -40)
    end

    -- Bar texture dropdown below dark tone
    if barTextureDrop then
        barTextureDrop:ClearAllPoints()
        local anchor = darkToneDrop or barModeDrop
        barTextureDrop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -40)
    end

    -- Gradient toggle + slider below bar texture
    if gradientCheck then
        gradientCheck:ClearAllPoints()
        local anchor = barTextureDrop or darkToneDrop or barModeDrop
        gradientCheck:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 16, -30)
    end

    if gradientSlider then
        gradientSlider:ClearAllPoints()
        local anchor = gradientCheck or barTextureDrop or barModeDrop
        gradientSlider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -16, -10)
    end

    -- Border toggle and style dropdown at the bottom of left column
    if borderCheck then
        borderCheck:ClearAllPoints()
        local anchor = gradientSlider or gradientCheck or barTextureDrop or barModeDrop
        borderCheck:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 16, -30)
    end

    if borderDrop and borderCheck then
        borderDrop:ClearAllPoints()
        borderDrop:SetPoint("TOPLEFT", borderCheck, "BOTTOMLEFT", -16, -10)
    end

    ------------------------------------------------------------
    -- RIGHT COLUMN: power bar visibility + HP text
    ------------------------------------------------------------
    local baseRightY = -180
    local stepY      = 30

    -- Background brightness slider on top
    if darkBgSlider then
        darkBgSlider:ClearAllPoints()
        darkBgSlider:SetPoint("TOPLEFT", barGroup, "TOPLEFT", rightX, baseRightY)
    end

    local currentY = baseRightY - 60
    local function PlaceCheck(btn)
        if not btn then return end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", barGroup, "TOPLEFT", rightX, currentY)
        currentY = currentY - stepY
    end

    PlaceCheck(targetPowerCheck)
    PlaceCheck(bossPowerCheck)
    PlaceCheck(playerPowerCheck)
    PlaceCheck(focusPowerCheck)

    -- Power bar height label + edit box
    if powerBarHeightEdit then
        local powerLabel = MSUF_FindLabelByText(barGroup, "Power bar height")
        if powerLabel then
            powerLabel:ClearAllPoints()
            powerLabel:SetPoint("TOPLEFT", barGroup, "TOPLEFT", rightX, currentY - 10)
        end

        powerBarHeightEdit:ClearAllPoints()
        if powerLabel then
            powerBarHeightEdit:SetPoint("LEFT", powerLabel, "RIGHT", 4, 0)
        else
            powerBarHeightEdit:SetPoint("TOPLEFT", barGroup, "TOPLEFT", rightX + 80, currentY - 10)
        end

        currentY = currentY - 50
    end

    -- HP text mode dropdown
    if hpTextModeDrop then
        local hpModeLabel = MSUF_FindLabelByText(barGroup, "HP text mode")
        if hpModeLabel then
            hpModeLabel:ClearAllPoints()
            hpModeLabel:SetPoint("TOPLEFT", barGroup, "TOPLEFT", rightX, currentY)
        end

        hpTextModeDrop:ClearAllPoints()
        hpTextModeDrop:SetPoint("TOPLEFT", barGroup, "TOPLEFT", rightX - 16, currentY - 24)
    end
end

-- Run after login once the options panel exists
local msufBarsLayoutFrame = CreateFrame("Frame")
msufBarsLayoutFrame:RegisterEvent("PLAYER_LOGIN")
msufBarsLayoutFrame:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.8, MSUF_RelayoutBarsOptions)
    else
        MSUF_RelayoutBarsOptions()
    end
end)
 