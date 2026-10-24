--- MSUF_Colors.lua
--- Runtime color service: a cached MSUF_DB.general resolver, Get/Set/Reset
--- accessors for every color category (global font, castbar, class, bar
--- background, NPC, pet, absorb overlays, power-bar background, aggro border,
--- bar outline), the coalesced and combat-deferred PushVisualUpdates /
--- PushCastbarVisualUpdates repaint requests, and the mouseover-highlight
--- shims that forward to MSUF.Highlight.
--- Loaded early (before Gameplay, Castbars, Borders etc.) so hot-path
--- consumers can call the getters at zero extra lookup cost.
--- Exposed as MSUF._colorsAPI / MSUF.Public.Colors plus a few MSUF_* globals
--- via ExportPublic. The options UI lives in the Menu2 pages of
--- MidnightSimpleUnitFrames_Options (e.g. MSUF_Menu2_AdvancedColors.lua).

local addonName, MSUF = ...
local FILE = "Runtime/MSUF_Colors.lua"
MSUF.Public = MSUF.Public or {}

local ExportPublic = MSUF.ExportPublic
local Require, Optional = MSUF.Require, MSUF.Optional
local PublicGlobals = MSUF.PublicGlobals
local string_lower = string.lower

--- REQUIRED: State/MSUF_Defaults.lua is listed unconditionally in the TOC and
--- exports MSUF_EnsureDB at its top level, long before this file. The cached
--- resolver below rebuilds MSUF_DB.general through it on every profile switch,
--- so a missing export must fail at load instead of silently skipping repair.
local EnsureDB = Require("MSUF_EnsureDB", FILE)
-- The colour getters below read the live profile inline (EnsureDB seeds it
-- while the client has none yet): power and reaction colours resolve per event.

-- Keep the namespace defaults distinct from the replaceable public palette.
local DEFAULT_FONT_COLORS = {
    white     = { 1.0, 1.0, 1.0 },
    black     = { 0.0, 0.0, 0.0 },
    red       = { 1.0, 0.0, 0.0 },
    green     = { 0.0, 1.0, 0.0 },
    blue      = { 0.0, 0.0, 1.0 },
    yellow    = { 1.0, 1.0, 0.0 },
    cyan      = { 0.0, 1.0, 1.0 },
    magenta   = { 1.0, 0.0, 1.0 },
    orange    = { 1.0, 0.5, 0.0 },
    purple    = { 0.6, 0.0, 0.8 },
    pink      = { 1.0, 0.6, 0.8 },
    turquoise = { 0.0, 0.9, 0.8 },
    grey      = { 0.5, 0.5, 0.5 },
    brown     = { 0.6, 0.3, 0.1 },
    gold      = { 1.0, 0.85, 0.1 },
}
MSUF.MSUF_FONT_COLORS = DEFAULT_FONT_COLORS
ExportPublic("MSUF_FONT_COLORS", Optional("MSUF_FONT_COLORS") or DEFAULT_FONT_COLORS)

ExportPublic("MSUF_GetNPCReactionColor", function(kind)
    local defaultR, defaultG, defaultB
    if kind == "friendly" then
        defaultR, defaultG, defaultB = 0, 1, 0
    elseif kind == "neutral" then
        defaultR, defaultG, defaultB = 1, 1, 0
    elseif kind == "enemy" then
        defaultR, defaultG, defaultB = 0.85, 0.10, 0.10
    elseif kind == "dead" then
        defaultR, defaultG, defaultB = 0.4, 0.4, 0.4
    else
        defaultR, defaultG, defaultB = 1, 1, 1
    end
    local db = MSUF_DB
    if not db then
        EnsureDB()
        db = MSUF_DB
    end
    db.npcColors = db.npcColors or {}
    local t = db.npcColors[kind]
    if t and t.r and t.g and t.b then
        return t.r, t.g, t.b
    end
    return defaultR, defaultG, defaultB
end)

ExportPublic("MSUF_GetClassBarColor", function(classToken)
    local defaultR, defaultG, defaultB = 0, 1, 0
    if not classToken then
        return defaultR, defaultG, defaultB
    end
    local db = MSUF_DB
    if not db then
        EnsureDB()
        db = MSUF_DB
    end
    db.classColors = db.classColors or {}
    local override = db.classColors[classToken]
    if override and override.r and override.g and override.b then
        return override.r, override.g, override.b
    end
    if type(override) == "string" and DEFAULT_FONT_COLORS and DEFAULT_FONT_COLORS[override] then
        local c = DEFAULT_FONT_COLORS[override]
        return c[1], c[2], c[3]
    end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if color then
        return color.r, color.g, color.b
    end
    return defaultR, defaultG, defaultB
end)

-- Some NPC unit tokens expose only the numeric UnitPowerType metadata. Keep
-- their configured resource color on the same token-keyed override path used
-- by players and previews instead of falling back to Blizzard's default RGB.
local POWER_TOKEN_BY_TYPE = {}
local CONFIGURABLE_POWER_TOKENS = {}
do
    local powerTypeEnum = Enum and Enum.PowerType
    local function RegisterPowerToken(enumKey, fallbackType, token)
        local numericType = powerTypeEnum and powerTypeEnum[enumKey]
        if type(numericType) ~= "number" then numericType = fallbackType end
        POWER_TOKEN_BY_TYPE[numericType] = token
        CONFIGURABLE_POWER_TOKENS[token] = true
    end

    RegisterPowerToken("Mana", 0, "MANA")
    RegisterPowerToken("Rage", 1, "RAGE")
    RegisterPowerToken("Focus", 2, "FOCUS")
    RegisterPowerToken("Energy", 3, "ENERGY")
    RegisterPowerToken("RunicPower", 6, "RUNIC_POWER")
    RegisterPowerToken("LunarPower", 8, "LUNAR_POWER")
    RegisterPowerToken("Maelstrom", 11, "MAELSTROM")
    RegisterPowerToken("Insanity", 13, "INSANITY")
    RegisterPowerToken("Fury", 17, "FURY")
    RegisterPowerToken("Pain", 18, "PAIN")
    RegisterPowerToken("Essence", 19, "ESSENCE")
end

local function NormalizePowerToken(powerType, powerToken)
    if type(powerToken) == "string" and powerToken ~= "" then return powerToken end
    return type(powerType) == "number" and POWER_TOKEN_BY_TYPE[powerType] or nil
end

local function MSUF_GetPowerBarColor(powerType, powerToken)
    powerToken = NormalizePowerToken(powerType, powerToken)
    if not powerToken then
        return nil
    end
    local db = MSUF_DB
    if not db then
        EnsureDB()
        db = MSUF_DB
    end
    local g = db.general
    local ov = g and g.powerColorOverrides
    local c = ov and ov[powerToken] or nil
    if type(c) ~= "table" then
        return nil
    end
    local r, gg, b
    if type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
        r, gg, b = c.r, c.g, c.b
    else
        r, gg, b = c[1], c[2], c[3]
    end
    if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
        return r, gg, b
    end
    return nil
end
ExportPublic("MSUF_GetPowerBarColor", MSUF_GetPowerBarColor)

local function MSUF_GetResolvedPowerColor(powerType, powerToken)
    powerToken = NormalizePowerToken(powerType, powerToken)
    local r, g, b = MSUF_GetPowerBarColor(powerType, powerToken)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return r, g, b
    end

    local snap = MSUF._PBCSnap
    if type(snap) == "table" then
        if type(powerToken) == "string" and snap[powerToken] then
            local c = snap[powerToken]
            return c.r, c.g, c.b
        end
        if type(powerType) == "number" and snap[powerType] then
            local c = snap[powerType]
            return c.r, c.g, c.b
        end
    end

    local pbc = PowerBarColor
    if type(powerToken) == "string" and pbc and pbc[powerToken] then
        local c = pbc[powerToken]
        local r = c.r or c[1]
        local g = c.g or c[2]
        local b = c.b or c[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    if type(powerType) == "number" and pbc and pbc[powerType] then
        local c = pbc[powerType]
        local r = c.r or c[1]
        local g = c.g or c[2]
        local b = c.b or c[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    if CONFIGURABLE_POWER_TOKENS[powerToken] == true then
        -- Matches the Colors menu's PowerDefaultRGB fallback. Essence has no
        -- Blizzard PowerBarColor entry on current PTR/live data, so without
        -- this final branch Reset would preview gray but render as Mana blue.
        return 0.8, 0.8, 0.8
    end
    return nil
end
ExportPublic("MSUF_GetResolvedPowerColor", MSUF_GetResolvedPowerColor)
MSUF.MSUF_GetResolvedPowerColor = MSUF_GetResolvedPowerColor

local function MSUF_GetConfiguredFontColor()
    local db = MSUF_DB
    if not db then
        EnsureDB()
        db = MSUF_DB
    end
    local g = db.general or {}
    if g.useCustomFontColor and g.fontColorCustomR and g.fontColorCustomG and g.fontColorCustomB then
        return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
    end
    local key = (g.fontColor or "white"):lower()
    local color = DEFAULT_FONT_COLORS[key] or DEFAULT_FONT_COLORS.white
    return color[1], color[2], color[3]
end
ExportPublic("MSUF_GetConfiguredFontColor", MSUF_GetConfiguredFontColor)
MSUF.MSUF_GetConfiguredFontColor = MSUF_GetConfiguredFontColor

local MSUF_COLOR_OBJECT_CACHE = {}
local MSUF_DEFAULT_COLOR_OBJECT

local function DefaultColorObject()
    if not MSUF_DEFAULT_COLOR_OBJECT then
        MSUF_DEFAULT_COLOR_OBJECT = CreateColor(1, 1, 1, 1)
    end
    return MSUF_DEFAULT_COLOR_OBJECT
end

local function MSUF_GetColorFromKey(key, fallbackColor)
    if type(key) ~= "string" then
        if fallbackColor then
            return fallbackColor
        end
        return DefaultColorObject()
    end
    -- Stored palette keys are already canonical. Avoid creating a lowered
    -- string on every runtime color refresh; mixed-case external callers keep
    -- the same case-insensitive fallback.
    local normalized = key
    local rgb = DEFAULT_FONT_COLORS[normalized]
    if not rgb then
        normalized = string_lower(key)
        rgb = DEFAULT_FONT_COLORS[normalized]
    end
    if rgb then
        local r, g, b = rgb[1], rgb[2], rgb[3]
        r, g, b = r or 1, g or 1, b or 1
        local cached = MSUF_COLOR_OBJECT_CACHE[normalized]
        if cached and cached.r == r and cached.g == g and cached.b == b then
            return cached.object
        end
        local object = CreateColor(r, g, b, 1)
        MSUF_COLOR_OBJECT_CACHE[normalized] = { r = r, g = g, b = b, object = object }
        return object
    end
    if fallbackColor then
        return fallbackColor
    end
    return DefaultColorObject()
end
MSUF.MSUF_GetColorFromKey = MSUF_GetColorFromKey
ExportPublic("MSUF_GetColorFromKey", MSUF_GetColorFromKey)

-- Numeric-only runtime consumers should not force a ColorObject into
-- existence. Share the canonical palette lookup while retaining the object
-- API above for consumers that need it.
local function MSUF_GetColorRGBFromKey(key)
    if type(key) ~= "string" then return nil end
    local rgb = DEFAULT_FONT_COLORS[key]
    if not rgb then rgb = DEFAULT_FONT_COLORS[string_lower(key)] end
    if not rgb then return nil end
    return rgb[1] or 1, rgb[2] or 1, rgb[3] or 1
end
MSUF.MSUF_GetColorRGBFromKey = MSUF_GetColorRGBFromKey
ExportPublic("MSUF_GetColorRGBFromKey", MSUF_GetColorRGBFromKey)

ExportPublic("MSUF_DARK_TONES", {
    black    = { 0.0, 0.0, 0.0 },
    darkgray = { 0.08, 0.08, 0.08 },
    softgray = { 0.16, 0.16, 0.16 },
})



---
--- Local shortcuts (core only - no UI-framework refs)
---
local RAID_CLASS_COLORS     = RAID_CLASS_COLORS
local C_Timer               = C_Timer
local type                  = type
local tonumber              = tonumber
local pairs                 = pairs
local next                  = next
local CreateFrame           = CreateFrame
local RunNextFrame          = Require("MSUF_RunNextFrame", FILE)
local COLOR_PUSH_DELAY      = 0.04

---
--- P0 perf: Cached DB resolver.
--- After PLAYER_LOGIN, EnsureDB() is a no-op and MSUF_DB.general
--- always exists. Every getter was paying for:
--- 1- global lookup (EnsureDB), 1- function call, 1- "or {}" guard
--- ~20 getters - N calls/sec = thousands of redundant ops.
---
--- _general() caches the ref and only refreshes when MSUF_DB identity
--- changes (profile switch replaces the entire table).
---
local _cachedDB, _cachedGen

local function _general()
    local db = MSUF_DB
    --- Full-profile imports deliberately keep the MSUF_DB root stable while
    --- replacing its `general` child. Validate both identities so getters and
    --- setters never keep operating on the detached pre-import table.
    if db and _cachedDB == db and _cachedGen == db.general then
        return _cachedGen
    end
    --- First call or profile switch: resolve fresh.
    EnsureDB()
    db = MSUF_DB
    if not db then return nil end
    db.general = db.general or {}
    _cachedDB  = db
    _cachedGen = db.general
    return _cachedGen
end

---
---
--- Helper: apply visual updates (COALESCED)
--- Color picker drag can fire 30+ times/sec. Without coalescing,
--- each drag fires UpdateAllFonts + RefreshAllFrames + ... per tick.
--- We batch locally; this runtime no longer depends on the global scheduler.
---
local _pushPending = false
local _castbarPushPending = false
local _colorCombatDeferred = false
local _castbarCombatDeferred = false
local _combatDeferFrame
local PushVisualUpdates
local PushCastbarVisualUpdates

local InCombat = MSUF.Util.InCombat

local function EnsureCombatDeferFrame()
    if _combatDeferFrame or type(CreateFrame) ~= "function" then
        return _combatDeferFrame
    end
    _combatDeferFrame = CreateFrame("Frame")
    _combatDeferFrame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" or InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local color = _colorCombatDeferred
        local castbar = _castbarCombatDeferred
        _colorCombatDeferred = false
        _castbarCombatDeferred = false
        if color and PushVisualUpdates then PushVisualUpdates() end
        if castbar and PushCastbarVisualUpdates then PushCastbarVisualUpdates() end
    end)
    return _combatDeferFrame
end

local function DeferVisualFlushUntilCombatEnds(kind)
    if kind == "castbar" then
        _castbarCombatDeferred = true
    else
        _colorCombatDeferred = true
    end
    local frame = EnsureCombatDeferFrame()
    if frame then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return true
end

local function _Call(fn, ...)
    if type(fn) ~= "function" then return false end
    fn(...)
    return true
end

--- The bar colours were refreshed by UF.RefreshColors just before, so only
--- the background visual is reapplied here.
local function _RefreshAllBarBackgroundVisuals()
    local applyBg = Require("MSUF_ApplyBarBackgroundVisual", FILE)
    local UF = MSUF and MSUF.UF
    local frames = UF and UF.frames
    if type(frames) ~= "table" then return end

    for _, frame in pairs(frames) do
        if frame and (frame.hpBarBG or frame.powerBarBG or frame.bg) then
            applyBg(frame)
        end
    end
end

local function _PushVisualUpdates_Flush()
    if InCombat() then
        _pushPending = false
        return DeferVisualFlushUntilCombatEnds("color")
    end
    --- PERF (4.22 Beta hotfix): pending flag stays TRUE during the entire
    --- flush body. Pending dedup remains correct: any PushVisualUpdates()
    --- call during this flush is dropped, and the next one after we finish
    --- schedules normally. Cleared at END.
    ---
    --- Same defense-in-depth pattern as _gfRosterFlush.
    --- UF.RefreshColors (MSUF_RefreshAllFrameColors) advances Config.serial
    --- before elements read color settings, so the lazy settings cache is
    --- rebuilt once on first use.
    Require("MSUF_RefreshAllFrameColors", FILE)()
    _RefreshAllBarBackgroundVisuals()
    Require("MSUF_UpdateCastbarVisuals", FILE)()
    if MSUF.MSUF_ApplyGameplayVisuals then
        _Call(MSUF.MSUF_ApplyGameplayVisuals)
    end
    --- Group Frames have their own render/dirty pipeline; refresh it explicitly
    --- so shared bar-color swatches (absorb/heal-absorb, borders, etc.) live-apply.
    do
        local gf = MSUF and MSUF.GF
        local refreshGFColors = (gf and gf.RefreshColors) or Require("MSUF_GF_RefreshColors", FILE)
        refreshGFColors()
    end

    --- No highlight-priority step here on purpose: the priority rows are
    --- options-menu widgets owned by the Bars page, which repaints them from
    --- its own page refresher. MSUF_PrioRows_Reinit was the pre-Menu2 panel
    --- hook and died with that panel; the runtime border order itself is part
    --- of the Borders refresh above.

    --- UF.RefreshColors already includes both Borders and Power, so the
    --- outline fanout does not run a second time here.
    Require("MSUF_ApplyRoundedUnitframes", FILE)()
    local auras = MSUF.MSUF_Auras3
    if auras and auras.RefreshNativeVisuals then auras.RefreshNativeVisuals() end
    _Call(Optional("MSUF_UFPreview_RequestRefresh"), "MSUF_COLOR_CHANGE")

    --- Repaint the mouseover highlight cache so colour/size edits apply live.
    Require("MSUF_RefreshMouseoverHighlight", FILE)()

    --- Pending flag cleared at END (see header comment for rationale).
    _pushPending = false
end

local function _PushCastbarVisuals_Flush()
    if InCombat() then
        _castbarPushPending = false
        return DeferVisualFlushUntilCombatEnds("castbar")
    end
    Require("MSUF_UpdateCastbarVisuals", FILE)()
    Require("MSUF_RefreshAllCastTargetTextColors", FILE)()
    _Call(Optional("MSUF_UFPreview_RequestRefresh"), "MSUF_CASTBAR_COLOR_CHANGE")
    _castbarPushPending = false
end

PushVisualUpdates = function()
    MSUF.Castbars.Config.Invalidate()
    local auras = MSUF.MSUF_Auras3
    if auras then auras.InvalidateNativeVisualInputs() end
    if InCombat() then return DeferVisualFlushUntilCombatEnds("color") end
    if _pushPending then return end
    _pushPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(COLOR_PUSH_DELAY, _PushVisualUpdates_Flush)
    else
        RunNextFrame(_PushVisualUpdates_Flush)
    end
end

PushCastbarVisualUpdates = function()
    MSUF.Castbars.Config.Invalidate()
    if InCombat() then return DeferVisualFlushUntilCombatEnds("castbar") end
    if _castbarPushPending then return end
    _castbarPushPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(COLOR_PUSH_DELAY, _PushCastbarVisuals_Flush)
    else
        RunNextFrame(_PushCastbarVisuals_Flush)
    end
end

--- ---------------------------------------------------------------------------
--- Mouseover highlight is now owned by MSUF.Highlight (Engine/Elements/
--- MSUF_UF_Highlight.lua): coldpath config cache + warmpath Show/Hide on
--- OnEnter/OnLeave. The old per-frame EnumerateFrames "fix" scan is gone.
--- These shims keep external callers working; they just repaint the cache.
--- ---------------------------------------------------------------------------
function MSUF.MSUF_FixMouseoverHighlightBindings()
    Require("MSUF_RefreshMouseoverHighlight", FILE)()
end
MSUF.MSUF_ScheduleMouseoverHighlightFix = MSUF.MSUF_FixMouseoverHighlightBindings


--- -
--- Color Get/Set API - data-driven where possible, hand-written for complex logic
--- -

--- Helper: simple RGB get from DB keys with defaults
local function _getRGB(rKey, gKey, bKey, defR, defG, defB)
    local g = _general()
    if not g then return defR, defG, defB end
    return g[rKey] or defR, g[gKey] or defG, g[bKey] or defB
end

--- Helper: simple RGBA get from DB keys with defaults
local function _getRGBA(rKey, gKey, bKey, aKey, defR, defG, defB, defA)
    local g = _general()
    if not g then return defR, defG, defB, defA end
    return g[rKey] or defR, g[gKey] or defG, g[bKey] or defB, g[aKey] or defA
end

--- Helper: simple RGB set + PushVisualUpdates
local function _setRGB(rKey, gKey, bKey, r, g, b, defR, defG, defB, pushFn)
    local gen = _general()
    if not gen then return end
    gen[rKey] = r or defR
    gen[gKey] = g or defG
    gen[bKey] = b or defB
    if type(pushFn) == "function" then pushFn() else PushVisualUpdates() end
end

--- Helper: simple RGBA set + PushVisualUpdates
local function _setRGBA(rKey, gKey, bKey, aKey, r, g, b, a, defR, defG, defB, defA, pushFn)
    local gen = _general()
    if not gen then return end
    gen[rKey] = r or defR
    gen[gKey] = g or defG
    gen[bKey] = b or defB
    gen[aKey] = a or defA
    if type(pushFn) == "function" then pushFn() else PushVisualUpdates() end
end

--- Helper: RGB get with palette fallback
local function _getRGBPalette(rKey, gKey, bKey, palKey, palDefault, defR, defG, defB)
    local g = _general()
    if not g then return defR, defG, defB end
    if g[rKey] and g[gKey] and g[bKey] then return g[rKey], g[gKey], g[bKey] end
    local pal = g[palKey]
    -- Namespace read: these getters run per paint, and a table read costs no call.
    local colors = PublicGlobals.MSUF_FONT_COLORS
    if pal and colors and colors[pal] then
        local c = colors[pal]
        return c[1], c[2], c[3]
    end
    if palDefault and colors and colors[palDefault] then
        local c = colors[palDefault]
        return c[1], c[2], c[3]
    end
    return defR, defG, defB
end

--- Helper: RGB get with tonumber guards + palette fallback
local function _getRGBTonumber(rKey, gKey, bKey, palKey, palDefault, defR, defG, defB)
    local g = _general()
    if not g then return defR, defG, defB end
    local r = tonumber(g[rKey])
    local gg = tonumber(g[gKey])
    local b = tonumber(g[bKey])
    if r and gg and b then return r, gg, b end
    local colors = PublicGlobals.MSUF_FONT_COLORS
    if g[palKey] and colors and colors[g[palKey]] then
        local c = colors[g[palKey]]
        return c[1], c[2], c[3]
    end
    if palDefault and colors and colors[palDefault] then
        local c = colors[palDefault]
        return c[1], c[2], c[3]
    end
    return defR, defG, defB
end

--- - Global Font Color -
local function GetGlobalFontColor()
    local g = _general()
    if not g then return 1, 1, 1 end
    if g.useCustomFontColor and g.fontColorCustomR and g.fontColorCustomG and g.fontColorCustomB then
        return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
    end
    local colors = PublicGlobals.MSUF_FONT_COLORS
    local color = colors and colors[(g.fontColor or "white"):lower()]
    if color then return color[1], color[2], color[3] end
    return 1, 1, 1
end
local function SetGlobalFontColor(r, g, b)
    local gen = _general()
    if not gen then return end
    gen.fontColorCustomR, gen.fontColorCustomG, gen.fontColorCustomB = r or 1, g or 1, b or 1
    gen.useCustomFontColor = true
    PushVisualUpdates()
end
local function ResetGlobalFontToPalette()
    local g = _general()
    if not g then return end
    g.useCustomFontColor = false
    g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB = nil, nil, nil
    PushVisualUpdates()
end

--- - Castbar Text Color -
local function GetCastbarTextColor()
    local g = _general()
    if not g then return GetGlobalFontColor() end
    if g.castbarFontR and g.castbarFontG and g.castbarFontB then return g.castbarFontR, g.castbarFontG, g.castbarFontB end
    return GetGlobalFontColor()
end
ExportPublic("MSUF_GetCastbarTextColor", GetCastbarTextColor)
local function SetCastbarTextColor(r, g, b)
    _setRGB("castbarFontR", "castbarFontG", "castbarFontB", r, g, b, 1, 1, 1, PushCastbarVisualUpdates)
end
local function ResetCastbarTextColorToGlobal()
    local g = _general()
    if not g then return end
    g.castbarFontR, g.castbarFontG, g.castbarFontB = nil, nil, nil
    PushCastbarVisualUpdates()
end

--- - Castbar Target Name Color -
--- The fourth return value preserves the legacy class-color fallback until a
--- user explicitly chooses a custom target-name color.
local function GetCastbarTargetNameColor()
    local g = _general()
    if not g then return 1, 1, 1, false end
    local r = tonumber(g.castbarTargetNameR)
    local green = tonumber(g.castbarTargetNameG)
    local b = tonumber(g.castbarTargetNameB)
    if r ~= nil and green ~= nil and b ~= nil then return r, green, b, true end
    return 1, 1, 1, false
end
ExportPublic("MSUF_GetCastbarTargetNameColor", GetCastbarTargetNameColor)
local function SetCastbarTargetNameColor(r, g, b)
    _setRGB("castbarTargetNameR", "castbarTargetNameG", "castbarTargetNameB", r, g, b, 1, 1, 1, PushCastbarVisualUpdates)
end
local function ResetCastbarTargetNameColor()
    local g = _general()
    if not g then return end
    g.castbarTargetNameR, g.castbarTargetNameG, g.castbarTargetNameB = nil, nil, nil
    PushCastbarVisualUpdates()
end

--- - Per-castbar detail text colors -
--- The castbar font path already reads these keys directly. This API exists so
--- the Options surfaces and the cast-target recolor path resolve them the same
--- way, and so an unset detail keeps inheriting the shared castbar text color
--- instead of being pinned. A complete triple is the opt-in signal, matching
--- the target-name contract above.
local CASTBAR_DETAIL_PREFIX = {
    player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus", boss = "bossCast",
    arena = "arenaCast",
}
local function CastbarDetailColorKey(unit, detail)
    if type(unit) ~= "string" or type(detail) ~= "string" or detail == "" then return nil end
    -- Boss/arena frames arrive as boss1..boss5/arena1..arena3 from the driver
    -- but share one config row per family.
    local prefix = CASTBAR_DETAIL_PREFIX[unit]
        or (unit:match("^boss%d*$") and "bossCast")
        or (unit:match("^arena%d*$") and "arenaCast")
        or nil
    if not prefix then return nil end
    return prefix .. detail .. "Color"
end
local function GetCastbarDetailTextColor(unit, detail)
    local g = _general()
    if not g then return 1, 1, 1, false end
    local key = CastbarDetailColorKey(unit, detail)
    if not key then return 1, 1, 1, false end
    local r, green, b = tonumber(g[key .. "R"]), tonumber(g[key .. "G"]), tonumber(g[key .. "B"])
    if r ~= nil and green ~= nil and b ~= nil then return r, green, b, true end
    return 1, 1, 1, false
end
ExportPublic("MSUF_GetCastbarDetailTextColor", GetCastbarDetailTextColor)
local function SetCastbarDetailTextColor(unit, detail, r, g, b)
    local key = CastbarDetailColorKey(unit, detail)
    if not key then return end
    _setRGB(key .. "R", key .. "G", key .. "B", r, g, b, 1, 1, 1, PushCastbarVisualUpdates)
end
ExportPublic("MSUF_SetCastbarDetailTextColor", SetCastbarDetailTextColor)
local function ResetCastbarDetailTextColor(unit, detail)
    local gen = _general()
    if not gen then return end
    local key = CastbarDetailColorKey(unit, detail)
    if not key then return end
    gen[key .. "R"], gen[key .. "G"], gen[key .. "B"] = nil, nil, nil
    PushCastbarVisualUpdates()
end
ExportPublic("MSUF_ResetCastbarDetailTextColor", ResetCastbarDetailTextColor)

--- - Castbar Border Color -
local function GetCastbarBorderColor() return _getRGBA("castbarBorderR", "castbarBorderG", "castbarBorderB", "castbarBorderA", 0, 0, 0, 1) end
local function SetCastbarBorderColor(r, g, b, a)
    _setRGBA("castbarBorderR", "castbarBorderG", "castbarBorderB", "castbarBorderA", r, g, b, a, 0, 0, 0, 1,
        PushCastbarVisualUpdates)
end
local function ResetCastbarBorderColor()
    local g = _general()
    if not g then return end
    g.castbarBorderR, g.castbarBorderG, g.castbarBorderB, g.castbarBorderA = nil, nil, nil, nil
    PushCastbarVisualUpdates()
end

--- - Castbar Background Color -
local function GetCastbarBackgroundColor()
    local g = _general()
    if not g then return 0.10, 0.10, 0.10, 0.85 end
    return tonumber(g.castbarBgR) or 0.10, tonumber(g.castbarBgG) or 0.10, tonumber(g.castbarBgB) or 0.10, tonumber(g.castbarBgA) or 0.85
end
ExportPublic("MSUF_GetCastbarBackgroundColor", GetCastbarBackgroundColor)
local function SetCastbarBackgroundColor(r, g, b, a)
    _setRGBA("castbarBgR", "castbarBgG", "castbarBgB", "castbarBgA", r, g, b, a, 0.10, 0.10, 0.10, 0.85,
        PushCastbarVisualUpdates)
end
local function ResetCastbarBackgroundColor()
    local g = _general()
    if not g then return end
    g.castbarBgR, g.castbarBgG, g.castbarBgB, g.castbarBgA = nil, nil, nil, nil
    PushCastbarVisualUpdates()
end

--- - Cast Colors (interruptible / non-interruptible / feedback) -
--- The menu's colour rows read these through MSUF._colorsAPI (with the palette
--- fallbacks). The public MSUF_GetInterruptibleCastColor,
--- MSUF_GetNonInterruptibleCastColor and MSUF_GetInterruptUnavailableCastColor
--- belong to Castbars/MSUF_CastbarUtils.lua: it loads after this file in every
--- TOC and always replaced these exports (custom RGB only; each castbar caller
--- owns its palette fallback), so this file no longer publishes them.
local function GetInterruptibleCastColor()
    return _getRGBPalette("castbarInterruptibleR", "castbarInterruptibleG", "castbarInterruptibleB",
        "castbarInterruptibleColor", "turquoise", 0, 0.9, 0.8)
end
local function SetInterruptibleCastColor(r, g, b)
    _setRGB("castbarInterruptibleR", "castbarInterruptibleG", "castbarInterruptibleB", r, g, b, 0, 0.9, 0.8,
        PushCastbarVisualUpdates)
end
local function GetNonInterruptibleCastColor()
    return _getRGBTonumber("castbarNonInterruptibleR", "castbarNonInterruptibleG", "castbarNonInterruptibleB",
        "castbarNonInterruptibleColor", "red", 0.4, 0.01, 0.01)
end
local function SetNonInterruptibleCastColor(r, g, b)
    _setRGB("castbarNonInterruptibleR", "castbarNonInterruptibleG", "castbarNonInterruptibleB", r, g, b, 0.4, 0.01, 0.01,
        PushCastbarVisualUpdates)
end
local function GetInterruptFeedbackCastColor()
    return _getRGBTonumber("castbarInterruptFeedbackR", "castbarInterruptFeedbackG", "castbarInterruptFeedbackB",
        "castbarInterruptFeedbackColor", "yellow", 1.0, 0.82, 0.0)
end
ExportPublic("MSUF_GetInterruptFeedbackCastColor", GetInterruptFeedbackCastColor)
local function SetInterruptFeedbackCastColor(r, g, b)
    _setRGB("castbarInterruptFeedbackR", "castbarInterruptFeedbackG", "castbarInterruptFeedbackB", r, g, b, 1.0, 0.82, 0.0,
        PushCastbarVisualUpdates)
end
local function GetInterruptUnavailableCastColor()
    return _getRGBTonumber("castbarInterruptUnavailableR", "castbarInterruptUnavailableG", "castbarInterruptUnavailableB",
        "castbarInterruptUnavailableColor", nil, 1.0, 0.494117647, 0.137254902)
end
local function SetInterruptUnavailableCastColor(r, g, b)
    _setRGB("castbarInterruptUnavailableR", "castbarInterruptUnavailableG", "castbarInterruptUnavailableB", r, g, b,
        1.0, 0.494117647, 0.137254902, PushCastbarVisualUpdates)
end

--- - Player Castbar Override -
local function GetPlayerCastbarOverrideEnabled() return (_general() or {}).playerCastbarOverrideEnabled and true or false end
local function SetPlayerCastbarOverrideEnabled(enabled)
    local g = _general()
    if not g then return end
    g.playerCastbarOverrideEnabled = enabled and true or false
    PushCastbarVisualUpdates()
end
local function GetPlayerCastbarOverrideMode() return (_general() or {}).playerCastbarOverrideMode or "COLOR" end
local function SetPlayerCastbarOverrideMode(mode)
    local g = _general()
    if not g then return end
    g.playerCastbarOverrideMode = mode
    PushCastbarVisualUpdates()
end
local function GetPlayerCastbarOverrideColor() return _getRGB("playerCastbarOverrideR", "playerCastbarOverrideG", "playerCastbarOverrideB", 0.0, 0.6, 1.0) end
local function SetPlayerCastbarOverrideColor(r, g, b)
    _setRGB("playerCastbarOverrideR", "playerCastbarOverrideG", "playerCastbarOverrideB", r, g, b, 0.0, 0.6, 1.0,
        PushCastbarVisualUpdates)
end

--- - Class Colors -
local CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
local function GetClassColor(token)
    local db = MSUF_DB
    if db and db.classColors and db.classColors[token] then
        local t = db.classColors[token]
        return t.r or 1, t.g or 1, t.b or 1
    end
    local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if rc then return rc.r, rc.g, rc.b end
    return 1, 1, 1
end
local function SetClassColor(token, r, g, b)
    local db = MSUF_DB
    if not db then return end
    db.classColors = db.classColors or {}
    db.classColors[token] = { r = r or 1, g = g or 1, b = b or 1 }
    PushVisualUpdates()
end
local function ResetAllClassColors()
    local db = MSUF_DB
    if db then db.classColors = nil end
    PushVisualUpdates()
end

--- - Class Bar Background Color -
local function GetClassBarBgColor() return _getRGBA("classBarBgR", "classBarBgG", "classBarBgB", "classBarBgA", 0, 0, 0, 1) end
local function SetClassBarBgColor(r, g, b, a) _setRGBA("classBarBgR", "classBarBgG", "classBarBgB", "classBarBgA", r, g, b, a, 0, 0, 0, 1) end
local function ResetClassBarBgColor()
    local g = _general()
    if not g then return end
    g.classBarBgR, g.classBarBgG, g.classBarBgB, g.classBarBgA = nil, nil, nil, nil
    PushVisualUpdates()
end

--- - Health Bar Background Fill / Color Mode -
local BAR_BG_FILL_MODES = { full = true, missing = true }
local BAR_BG_COLOR_MODES = { custom = true, match_health = true, class = true, health_gradient = true }

local function ResolveBarBgFillMode(g)
    local mode = g and g.barBgFillMode
    return BAR_BG_FILL_MODES[mode] and mode or "full"
end

local function ResolveBarBgColorMode(g)
    local mode = g and g.barBgColorMode
    if BAR_BG_COLOR_MODES[mode] then return mode end
    if g and g.barBgClassColor == true then return "class" end
    if g and g.barBgMatchHPColor == true then return "match_health" end
    return "custom"
end

local function SetStoredBarBgColorMode(g, mode)
    if not (g and BAR_BG_COLOR_MODES[mode]) then return false end
    g.barBgColorMode = mode
    -- Keep the retired toggle storage coherent for imports and third-party
    -- callers that still use the public compatibility APIs below.
    g.barBgMatchHPColor = mode == "match_health"
    g.barBgClassColor = mode == "class"
    return true
end

local function GetBarBgFillMode() return ResolveBarBgFillMode(_general()) end
local function SetBarBgFillMode(mode)
    local g = _general()
    if not (g and BAR_BG_FILL_MODES[mode]) then return false end
    g.barBgFillMode = mode
    PushVisualUpdates()
    return true
end

local function GetBarBgColorMode() return ResolveBarBgColorMode(_general()) end
local function SetBarBgColorMode(mode)
    local g = _general()
    if not SetStoredBarBgColorMode(g, mode) then return false end
    PushVisualUpdates()
    return true
end

local function GetBarBgMatchHP() return ResolveBarBgColorMode(_general()) == "match_health" end
local function SetBarBgMatchHP(v)
    local g = _general()
    if g then
        local current = ResolveBarBgColorMode(g)
        SetStoredBarBgColorMode(g, v and "match_health" or (current == "match_health" and "custom" or current))
        PushVisualUpdates()
    end
end
local function GetBarBgClassColor() return ResolveBarBgColorMode(_general()) == "class" end
local function SetBarBgClassColor(v)
    local g = _general()
    if g then
        local current = ResolveBarBgColorMode(g)
        SetStoredBarBgColorMode(g, v and "class" or (current == "class" and "custom" or current))
        PushVisualUpdates()
    end
end

--- - NPC Colors -
local NPC_TYPE_KEYS = { "npcBoss", "npcMiniboss", "npcCaster", "npcMelee", "npcRegular" }
local NPC_TYPE_UNITS = {
    { key = "npcTypeTarget", label = "Target" }, { key = "npcTypeFocus", label = "Focus" },
    { key = "npcTypeBoss", label = "Boss" }, { key = "npcTypeToT", label = "Target of Target" },
}

local function GetNPCColor(kind)
    local db = MSUF_DB
    if db and db.npcColors and db.npcColors[kind] then
        local t = db.npcColors[kind]
        return t.r or 0, t.g or 1, t.b or 0
    end
    local def = { friendly={0,1,0}, neutral={1,1,0}, enemy={0.85,0.10,0.10}, dead={0.4,0.4,0.4},
        npcBoss={0.74,0.11,0}, npcMiniboss={0.56,0,0.74}, npcCaster={0,0.45,0.74}, npcMelee={0.99,0.99,0.99}, npcRegular={0.70,0.56,0.33} }
    local d = def[kind] or def.enemy
    return d[1], d[2], d[3]
end
local function SetNPCColor(kind, r, g, b)
    local db = MSUF_DB
    if not db then return end
    db.npcColors = db.npcColors or {}
    db.npcColors[kind] = { r = r or 0, g = g or 1, b = b or 0 }
    PushVisualUpdates()
end
local function ResetAllNPCColors()
    local db = MSUF_DB
    if db then db.npcColors = nil end
    PushVisualUpdates()
end
local function GetNPCColorMode() return (_general() or {}).npcColorMode or "reaction" end
local function SetNPCColorMode(mode)
    local g = _general()
    if g then
        g.npcColorMode = mode
        PushVisualUpdates()
    end
end
local function GetNPCTypeColorBar()
    local g = _general()
    return not g or g.npcTypeColorBar ~= false
end
local function SetNPCTypeColorBar(v)
    local g = _general()
    if g then
        g.npcTypeColorBar = v and true or false
        PushVisualUpdates()
    end
end
local function GetNPCTypeColorText()
    local g = _general()
    return not g or g.npcTypeColorText ~= false
end
local function SetNPCTypeColorText(v)
    local g = _general()
    if g then
        g.npcTypeColorText = v and true or false
        PushVisualUpdates()
    end
end
local function GetNPCClassColorBar()
    local g = _general()
    return g and g.npcClassColorBar == true or false
end
local function SetNPCClassColorBar(v)
    local g = _general()
    if g then
        g.npcClassColorBar = v and true or false
        PushVisualUpdates()
    end
end
local function ResetNPCTypeColors()
    local db = MSUF_DB
    local colors = db and db.npcColors
    if type(colors) == "table" then
        for i = 1, #NPC_TYPE_KEYS do colors[NPC_TYPE_KEYS[i]] = nil end
        if next(colors) == nil then db.npcColors = nil end
    end
    PushVisualUpdates()
end
local function GetNPCTypePerUnit(key)
    local g = _general()
    return not g or g[key] ~= false
end
local function SetNPCTypePerUnit(key, v)
    local g = _general()
    if g then
        g[key] = v and true or false
        PushVisualUpdates()
    end
end

--- - Pet Frame Color -
local function GetPetFrameColor() return _getRGB("petFrameColorR", "petFrameColorG", "petFrameColorB", 0, 0.8, 0) end
local function SetPetFrameColor(r, g, b) _setRGB("petFrameColorR", "petFrameColorG", "petFrameColorB", r, g, b, 0, 0.8, 0) end

--- - Absorb / Heal-Absorb Overlay Colors -
--- Keys aligned with the readers used by main UF, GF Render, GF Core preview,
--- GF AuraPreview, and the bar-color reset in Options_Colors. The picker used
--- to write `absorbColor*` / `healAbsorbColor*` while every reader consumed
--- `absorbBarColor*` / `healAbsorbBarColor*` - so color changes never landed.
--- One-time migration of the legacy keys is done in MSUF_Defaults.
local function GetAbsorbOverlayColor()
    return _getRGBA("absorbBarColorR", "absorbBarColorG", "absorbBarColorB", "absorbBarColorA", 1.0, 1.0, 1.0, 0.45)
end
local function SetAbsorbOverlayColor(r, g, b, a)
    _setRGBA("absorbBarColorR", "absorbBarColorG", "absorbBarColorB", "absorbBarColorA", r, g, b, a, 1.0, 1.0, 1.0, 0.45)
end
local function GetHealAbsorbOverlayColor()
    return _getRGBA("healAbsorbBarColorR", "healAbsorbBarColorG", "healAbsorbBarColorB", "healAbsorbBarColorA",
        0.7, 0.0, 0.0, 0.45)
end
local function SetHealAbsorbOverlayColor(r, g, b, a)
    _setRGBA("healAbsorbBarColorR", "healAbsorbBarColorG", "healAbsorbBarColorB", "healAbsorbBarColorA", r, g, b, a,
        0.7, 0.0, 0.0, 0.45)
end

--- - Power Bar Background -
local function GetPowerBarBackgroundColor()
    return _getRGBA("powerBarBgColorR", "powerBarBgColorG", "powerBarBgColorB", "powerBarBgColorA", 0, 0, 0, 1)
end
local function SetPowerBarBackgroundColor(r, g, b, a)
    _setRGBA("powerBarBgColorR", "powerBarBgColorG", "powerBarBgColorB", "powerBarBgColorA", r, g, b, a, 0, 0, 0, 1)
end
local function GetPowerBarBackgroundMatchHP() return (_general() or {}).powerBarBgMatchBarColor and true or false end
local function SetPowerBarBackgroundMatchHP(v)
    local g = _general()
    if g then
        g.powerBarBgMatchBarColor = v and true or false
        PushVisualUpdates()
    end
end

--- - Aggro Border -
local function GetAggroBorderColor()
    local g = _general()
    if not g then return 1.0, 0.5, 0.0 end
    return tonumber(g.hlAggroColorR) or tonumber(g.aggroBorderColorR) or tonumber(g.aggroBorderR) or 1.0,
           tonumber(g.hlAggroColorG) or tonumber(g.aggroBorderColorG) or tonumber(g.aggroBorderG) or 0.5,
           tonumber(g.hlAggroColorB) or tonumber(g.aggroBorderColorB) or tonumber(g.aggroBorderB) or 0.0
end
local function SetAggroBorderColor(r, g, b)
    local gen = _general()
    if not gen then return end
    gen.hlAggroColorR = r or 1.0
    gen.hlAggroColorG = g or 0.5
    gen.hlAggroColorB = b or 0.0
    gen.aggroBorderColorR, gen.aggroBorderColorG, gen.aggroBorderColorB = gen.hlAggroColorR, gen.hlAggroColorG, gen.hlAggroColorB
    gen.aggroBorderR, gen.aggroBorderG, gen.aggroBorderB = gen.hlAggroColorR, gen.hlAggroColorG, gen.hlAggroColorB
    PushVisualUpdates()
end

local function GetBarOutlineColor() return _getRGB("barOutlineColorR", "barOutlineColorG", "barOutlineColorB", 0, 0, 0) end
local function SetBarOutlineColor(r, g, b)
    local general = _general()
    if general then
        general.barOutlineColorMode = nil
        general.barOutlineColorA = 1
    end
    _setRGB("barOutlineColorR", "barOutlineColorG", "barOutlineColorB", r, g, b, 0, 0, 0)
end
ExportPublic("MSUF_GetBarOutlineColor", GetBarOutlineColor)

--- -
--- Export table
--- -
MSUF._colorsAPI = {
    PushVisualUpdates               = PushVisualUpdates,
    PushCastbarVisualUpdates        = PushCastbarVisualUpdates,
    GetGlobalFontColor              = GetGlobalFontColor,
    SetGlobalFontColor              = SetGlobalFontColor,
    ResetGlobalFontToPalette        = ResetGlobalFontToPalette,
    GetCastbarTextColor             = GetCastbarTextColor,
    SetCastbarTextColor             = SetCastbarTextColor,
    ResetCastbarTextColorToGlobal   = ResetCastbarTextColorToGlobal,
    GetCastbarTargetNameColor       = GetCastbarTargetNameColor,
    SetCastbarTargetNameColor       = SetCastbarTargetNameColor,
    ResetCastbarTargetNameColor     = ResetCastbarTargetNameColor,
    GetCastbarDetailTextColor       = GetCastbarDetailTextColor,
    SetCastbarDetailTextColor       = SetCastbarDetailTextColor,
    ResetCastbarDetailTextColor     = ResetCastbarDetailTextColor,
    GetCastbarBorderColor           = GetCastbarBorderColor,
    SetCastbarBorderColor           = SetCastbarBorderColor,
    ResetCastbarBorderColor         = ResetCastbarBorderColor,
    GetCastbarBackgroundColor       = GetCastbarBackgroundColor,
    SetCastbarBackgroundColor       = SetCastbarBackgroundColor,
    ResetCastbarBackgroundColor     = ResetCastbarBackgroundColor,
    GetInterruptibleCastColor       = GetInterruptibleCastColor,
    SetInterruptibleCastColor       = SetInterruptibleCastColor,
    GetNonInterruptibleCastColor    = GetNonInterruptibleCastColor,
    SetNonInterruptibleCastColor    = SetNonInterruptibleCastColor,
    GetInterruptFeedbackCastColor   = GetInterruptFeedbackCastColor,
    SetInterruptFeedbackCastColor   = SetInterruptFeedbackCastColor,
    GetInterruptUnavailableCastColor = GetInterruptUnavailableCastColor,
    SetInterruptUnavailableCastColor = SetInterruptUnavailableCastColor,
    GetPlayerCastbarOverrideEnabled = GetPlayerCastbarOverrideEnabled,
    SetPlayerCastbarOverrideEnabled = SetPlayerCastbarOverrideEnabled,
    GetPlayerCastbarOverrideMode    = GetPlayerCastbarOverrideMode,
    SetPlayerCastbarOverrideMode    = SetPlayerCastbarOverrideMode,
    GetPlayerCastbarOverrideColor   = GetPlayerCastbarOverrideColor,
    SetPlayerCastbarOverrideColor   = SetPlayerCastbarOverrideColor,
    GetClassColor                   = GetClassColor,
    SetClassColor                   = SetClassColor,
    ResetAllClassColors             = ResetAllClassColors,
    CLASS_TOKENS                    = CLASS_TOKENS,
    GetClassBarBgColor              = GetClassBarBgColor,
    SetClassBarBgColor              = SetClassBarBgColor,
    ResetClassBarBgColor            = ResetClassBarBgColor,
    GetBarBgFillMode                = GetBarBgFillMode,
    SetBarBgFillMode                = SetBarBgFillMode,
    GetBarBgColorMode               = GetBarBgColorMode,
    SetBarBgColorMode               = SetBarBgColorMode,
    GetBarBgMatchHP                 = GetBarBgMatchHP,
    SetBarBgMatchHP                 = SetBarBgMatchHP,
    GetBarBgClassColor              = GetBarBgClassColor,
    SetBarBgClassColor              = SetBarBgClassColor,
    GetNPCColor                     = GetNPCColor,
    SetNPCColor                     = SetNPCColor,
    ResetAllNPCColors               = ResetAllNPCColors,
    GetNPCColorMode                 = GetNPCColorMode,
    SetNPCColorMode                 = SetNPCColorMode,
    GetNPCTypeColorBar              = GetNPCTypeColorBar,
    SetNPCTypeColorBar              = SetNPCTypeColorBar,
    GetNPCTypeColorText             = GetNPCTypeColorText,
    SetNPCTypeColorText             = SetNPCTypeColorText,
    GetNPCClassColorBar             = GetNPCClassColorBar,
    SetNPCClassColorBar             = SetNPCClassColorBar,
    ResetNPCTypeColors              = ResetNPCTypeColors,
    NPC_TYPE_KEYS                   = NPC_TYPE_KEYS,
    NPC_TYPE_UNITS                  = NPC_TYPE_UNITS,
    GetNPCTypePerUnit               = GetNPCTypePerUnit,
    SetNPCTypePerUnit               = SetNPCTypePerUnit,
    GetPetFrameColor                = GetPetFrameColor,
    SetPetFrameColor                = SetPetFrameColor,
    GetAbsorbOverlayColor           = GetAbsorbOverlayColor,
    SetAbsorbOverlayColor           = SetAbsorbOverlayColor,
    GetHealAbsorbOverlayColor       = GetHealAbsorbOverlayColor,
    SetHealAbsorbOverlayColor       = SetHealAbsorbOverlayColor,
    GetPowerBarBackgroundColor      = GetPowerBarBackgroundColor,
    SetPowerBarBackgroundColor      = SetPowerBarBackgroundColor,
    GetAggroBorderColor             = GetAggroBorderColor,
    SetAggroBorderColor             = SetAggroBorderColor,
    GetBarOutlineColor              = GetBarOutlineColor,
    SetBarOutlineColor              = SetBarOutlineColor,
    GetPowerBarBackgroundMatchHP    = GetPowerBarBackgroundMatchHP,
    SetPowerBarBackgroundMatchHP    = SetPowerBarBackgroundMatchHP,
}
MSUF.Public.Colors = MSUF._colorsAPI
