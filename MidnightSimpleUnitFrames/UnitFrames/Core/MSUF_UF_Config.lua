local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local UF = MSUF.UF
UF.Config = UF.Config or {}
local Config = UF.Config

local type = type
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local byte, sub = string.byte, string.sub
local max, abs, floor = math.max, math.abs, math.floor
local InCombatLockdown = _G.InCombatLockdown
local wipe = _G.wipe or table.wipe or function(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

local WHITE = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local CDM_WIDTH_FRAMES = {
    cooldown = "EssentialCooldownViewer",
    utility = "UtilityCooldownViewer",
    tracked_buffs = "BuffIconCooldownViewer",
}
local COOLDOWN_VIEWER_FRAMES = {
    EssentialCooldownViewer = true,
    UtilityCooldownViewer = true,
    BuffIconCooldownViewer = true,
}
local ECV_ANCHORS = {
    player = { "RIGHT", "LEFT", -20, 0 },
    target = { "LEFT", "RIGHT", 20, 0 },
    focus = { "TOP", "LEFT", 0, 0 },
    targettarget = { "TOP", "RIGHT", 0, -40 },
    focustarget = { "TOP", "RIGHT", 0, 40 },
}

local DEFAULTS = {
    player = { width = 275, height = 40, x = -256, y = -180, showName = false, showPower = true },
    target = { width = 275, height = 40, x = 320, y = -180, showName = true, showPower = true },
    focus = { width = 180, height = 30, x = -260, y = -300, showName = true, showPower = false },
    targettarget = { width = 180, height = 30, x = 220, y = -300, showName = false, showPower = false },
    focustarget = { width = 180, height = 30, x = 260, y = 180, showName = true, showPower = false },
    pet = { width = 220, height = 30, x = -275, y = -250, showName = true, showPower = true },
    boss = { width = 180, height = 30, x = 500, y = 180, showName = true, showPower = false },
}

local POWER_KEYS = {
    player = "showPlayerPowerBar",
    target = "showTargetPowerBar",
    focus = "showFocusPowerBar",
    boss = "showBossPowerBar",
}

local function IsCooldownViewerFrameName(frameName)
    return COOLDOWN_VIEWER_FRAMES[frameName] == true
end

local CASTBAR_KEYS = {
    player = "enablePlayerCastbar",
    target = "enableTargetCastbar",
    focus = "enableFocusCastbar",
    boss = "enableBossCastbar",
}

local CLASS_TOKENS = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local NPC_COLOR_DEFAULTS = {
    friendly = { 0, 1, 0 },
    neutral = { 1, 1, 0 },
    enemy = { 0.85, 0.10, 0.10 },
    dead = { 0.4, 0.4, 0.4 },
    npcBoss = { 0.74, 0.11, 0 },
    npcMiniboss = { 0.56, 0, 0.74 },
    npcCaster = { 0, 0.45, 0.74 },
    npcMelee = { 0.99, 0.99, 0.99 },
    npcRegular = { 0.70, 0.56, 0.33 },
}

local dbInitialized = false

local function EnsureDB()
    if not dbInitialized or type(_G.MSUF_DB) ~= "table" then
        if type(_G.MSUF_InitProfiles) == "function" then
            _G.MSUF_InitProfiles()
        end
        if type(_G.MSUF_EnsureDB) == "function" then
            _G.MSUF_EnsureDB()
        end
        dbInitialized = true
    end
    if type(_G.MSUF_DB) ~= "table" then
        _G.MSUF_DB = {}
    end
    return _G.MSUF_DB
end

local function Number(value, fallback)
    value = tonumber(value)
    if value == nil then
        return fallback
    end
    return value
end

local function Bool(value, fallback)
    if value == nil then
        return fallback
    end
    return value == true
end

local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then
        value = fallback
    end
    if value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

local function NormalizeDispelDetectTrigger(value)
    local ds = UF and UF.DispelState
    if ds and type(ds.NormalizeDetectTrigger) == "function" then
        return ds.NormalizeDetectTrigger(value)
    end
    value = tostring(value or ""):upper()
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then
        return "DISPEL_TYPE"
    elseif value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then
        return "ANY_DEBUFF"
    elseif value == "PLAYER_CAST" or value == "CAST_BY_ME" or value == "MY_DEBUFF" then
        return "PLAYER_CAST"
    end
    return "BY_ME"
end

local function NormalizeDispelOverlayTrigger(value)
    local ds = UF and UF.DispelState
    if ds and type(ds.NormalizeOverlayTrigger) == "function" then
        return ds.NormalizeOverlayTrigger(value)
    end
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "INHERIT" or value == "SAME" then
        return "BORDER"
    end
    return NormalizeDispelDetectTrigger(value)
end

local function NormalizeDispelOverlayStyle(value)
    if value == "TOP" or value == "BOTTOM" or value == "LEFT" or value == "RIGHT" then
        return value
    end
    return "FULL"
end

local function OutlineModeEnabled(value, fallback)
    if value == nil then value = fallback end
    if value == true or value == false then return value end
    value = tonumber(value)
    if value == nil then return fallback == true end
    return value == 1
end

local function ScopedValue(conf, general, key, fallback)
    if conf and conf.hlOverride == true and conf[key] ~= nil then
        return conf[key]
    end
    if general and general[key] ~= nil then
        return general[key]
    end
    return fallback
end

local function CopyColor(dst, r, g, b, a)
    dst.r = Number(r, dst.r or 1)
    dst.g = Number(g, dst.g or 1)
    dst.b = Number(b, dst.b or 1)
    dst.a = Number(a, dst.a or 1)
end

local function ResolveBarMode(general)
    local mode = general and general.barMode
    if type(mode) == "string" then
        mode = mode:lower()
    end
    if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then
        if general and general.useClassColors == true then
            mode = "class"
        elseif general and general.darkMode == true then
            mode = "dark"
        else
            mode = "dark"
        end
    end
    if mode == "gradient" and general and general.enableHealthGradient == false then
        mode = "class"
    end
    return mode
end

local function ResolvePowerMode(general)
    local mode = general and (general.powerColorMode or general.powerBarColorMode)
    if type(mode) == "string" then
        mode = mode:lower()
    end
    if mode == "class" or mode == "static" or mode == "unified" or mode == "dark" then
        return mode
    end
    return "power"
end

local function ResolveDarkColor(general, dst)
    local gray = Number(general and (general.darkBarGray or general.darkBgBrightness), 0.07)
    if gray > 1 then
        gray = gray / 100
    end
    CopyColor(dst, general and general.darkBarR or gray, general and general.darkBarG or gray, general and general.darkBarB or gray, 1)
end

local function ResolveTextColor(general, dst)
    dst = dst or {}
    local getColor = _G.MSUF_GetConfiguredFontColor or MSUF.MSUF_GetConfiguredFontColor
    if type(getColor) == "function" then
        local r, g, b = getColor()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            CopyColor(dst, r, g, b, 1)
            return dst
        end
    end
    if general and general.useCustomFontColor == true
        and type(general.fontColorCustomR) == "number"
        and type(general.fontColorCustomG) == "number"
        and type(general.fontColorCustomB) == "number" then
        CopyColor(dst, general.fontColorCustomR, general.fontColorCustomG, general.fontColorCustomB, 1)
        return dst
    end
    local palette = MSUF.MSUF_FONT_COLORS or _G.MSUF_FONT_COLORS
    local key = general and general.fontColor
    if type(key) == "string" and palette then
        local c = palette[key:lower()]
        if c then
            CopyColor(dst, c.r or c[1], c.g or c[2], c.b or c[3], c.a or c[4] or 1)
            return dst
        end
    end
    CopyColor(dst, 1, 1, 1, 1)
    return dst
end

local function ResolveBgAlpha(general, bars)
    local alpha = bars and bars.barBackgroundAlpha
    if type(alpha) == "number" then
        return Clamp01(alpha / 100, 0.9)
    end
    return Clamp01(general and general.barBackgroundAlpha, 0.9)
end

local function DarkTint(general, r, g, b)
    if general and general.darkMode == true and general.darkBgCustomColor ~= true then
        local brightness = Clamp01(general.darkBgBrightness, 0.25)
        return (r or 0) * brightness, (g or 0) * brightness, (b or 0) * brightness
    end
    return r or 0, g or 0, b or 0
end

local function ResolveHealthBackground(general, bars, health, dst)
    dst = dst or {}
    local r, g, b, a
    local getBg = _G.MSUF_GetBarBackgroundTintRGBA
    if type(getBg) == "function" then
        r, g, b, a = getBg()
    else
        r, g, b = DarkTint(general, Number(general and general.classBarBgR, 0), Number(general and general.classBarBgG, 0), Number(general and general.classBarBgB, 0))
        a = 0.9
    end
    if general and general.barBgMatchHPColor == true and health then
        r, g, b = DarkTint(general, health.r, health.g, health.b)
    end
    CopyColor(dst, r, g, b, (Number(a, 0.9)) * ResolveBgAlpha(general, bars))
    return dst
end

local function ResolvePowerBackground(general, bars, health, dst)
    dst = dst or {}
    local r, g, b, a
    local getBg = _G.MSUF_GetPowerBarBackgroundTintRGBA
    if type(getBg) == "function" then
        r, g, b, a = getBg()
    else
        r, g, b = DarkTint(general, Number(general and general.powerBarBgColorR, Number(general and general.classBarBgR, 0)), Number(general and general.powerBarBgColorG, Number(general and general.classBarBgG, 0)), Number(general and general.powerBarBgColorB, Number(general and general.classBarBgB, 0)))
        a = 0.9
    end
    if (general and general.powerBarBgMatchBarColor == true) or (bars and bars.powerBarBgMatchBarColor == true) then
        r, g, b = DarkTint(general, health and health.r or r, health and health.g or g, health and health.b or b)
    end
    CopyColor(dst, r, g, b, (Number(a, 0.9)) * ResolveBgAlpha(general, bars))
    return dst
end

local function NormalizeAbsorbTestScope(scope)
    scope = tostring(scope or "shared"):lower()
    scope = scope:gsub("%s+", "")
    scope = scope:gsub("%-", "_")
    if scope == "" or scope == "all" or scope == "global" then
        return "shared"
    elseif scope == "gf_party" or scope == "group_party" or scope == "gfparty" then
        return "party"
    elseif scope == "gf_raid" or scope == "gf_mythicraid" or scope == "group_raid" or scope == "gfraid" or scope == "mythic" or scope == "mythicraid" then
        return "raid"
    elseif scope == "focus_target" then
        return "focustarget"
    elseif scope == "targetoftarget" or scope == "tot" then
        return "targettarget"
    end
    return scope
end

local function AbsorbTestEnabledForKey(key)
    if _G.MSUF_AbsorbTextureTestMode ~= true then
        return false
    end
    local scope = NormalizeAbsorbTestScope(_G.MSUF_AbsorbTextureTestScope)
    key = NormalizeAbsorbTestScope(key)
    return scope == "shared" or scope == key
end

_G.MSUF_SetAbsorbTextureTestMode = _G.MSUF_SetAbsorbTextureTestMode or function(enabled, scope)
    _G.MSUF_AbsorbTextureTestMode = enabled == true
    _G.MSUF_AbsorbTextureTestScope = enabled and NormalizeAbsorbTestScope(scope) or nil
end

_G.MSUF_ClearAbsorbTextureTestMode = _G.MSUF_ClearAbsorbTextureTestMode or function()
    _G.MSUF_AbsorbTextureTestMode = false
    _G.MSUF_AbsorbTextureTestScope = nil
end

_G.MSUF_ShouldShowAbsorbTextureTest = _G.MSUF_ShouldShowAbsorbTextureTest or function(frame, scope)
    if _G.MSUF_AbsorbTextureTestMode ~= true then
        return false
    end
    local wanted = NormalizeAbsorbTestScope(_G.MSUF_AbsorbTextureTestScope)
    if wanted == "shared" then
        return true
    end
    local key = scope
        or frame and (frame.configKey or frame.MSUFUnitKey or frame._msufGFKind or frame.unitKey)
        or nil
    return wanted == NormalizeAbsorbTestScope(key)
end

local function NormalizeHealthTextMode(mode, fallback)
    if mode == nil then
        return fallback
    end
    if mode == "FULL_ONLY" then
        return "CURRENT"
    elseif mode == "PERCENT_ONLY" then
        return "PERCENT"
    elseif mode == "FULL_SLASH_MAX" then
        return "CURMAX"
    elseif mode == "FULL_PLUS_PERCENT" then
        return "CURPERCENT"
    elseif mode == "PERCENT_PLUS_FULL" then
        return "PERCENTCUR"
    end
    return mode
end

local function NormalizePowerTextMode(mode, fallback)
    if mode == nil then
        return fallback
    end
    if mode == "FULL_ONLY" then
        return "CURRENT"
    elseif mode == "PERCENT_ONLY" then
        return "PERCENT"
    elseif mode == "FULL_SLASH_MAX" then
        return "CURMAX"
    elseif mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL" then
        return "CURPERCENT"
    end
    return mode
end

local function ResolveNameShortening(db, general, conf, unit, text)
    local shorten = db and db.shortenNames == true
    local maxChars = Number(general and general.shortenNameMaxChars, 6)
    local side = tostring(general and general.shortenNameClipSide or "LEFT"):upper()
    local dots = general and general.shortenNameShowDots
    dots = dots == nil or dots == true

    if conf and conf.fontOverride == true then
        if conf.shortenNames ~= nil then
            shorten = conf.shortenNames == true
        elseif conf.nameShortenEnabled ~= nil then
            shorten = conf.nameShortenEnabled == true
        end
        maxChars = Number(conf.shortenNameMaxChars or conf.nameMaxChars, maxChars)
        side = tostring(conf.shortenNameClipSide or conf.nameClipSide or side):upper()
        if conf.shortenNameShowDots ~= nil then
            dots = conf.shortenNameShowDots == true
        elseif conf.nameNoEllipsis ~= nil then
            dots = conf.nameNoEllipsis ~= true
        end
    end

    if unit == "player" and not (conf and conf.fontOverride == true and (conf.shortenNames == true or conf.nameShortenEnabled == true)) then
        shorten = false
    end
    if side ~= "RIGHT" then
        side = "LEFT"
    end

    maxChars = floor((tonumber(maxChars) or 6) + 0.5)
    if maxChars < 4 then
        maxChars = 4
    elseif maxChars > 40 then
        maxChars = 40
    end

    text.nameShorten = shorten == true
    text.nameShortenMax = maxChars
    text.nameShortenSide = side
    text.nameShortenDots = dots == true
end

local function ResolveNameColorFlags(general, conf)
    local classColor = general and general.nameClassColor == true
    local npcColor = general and general.npcNameRed == true
    if conf and conf.fontOverride == true then
        if conf.nameClassColor ~= nil then
            classColor = conf.nameClassColor == true
        end
        if conf.npcNameRed ~= nil then
            npcColor = conf.npcNameRed == true
        end
    end
    return classColor, npcColor
end

local function Utf8Prefix(value, maxChars)
    value = tostring(value or "")
    maxChars = tonumber(maxChars) or 0
    if value == "" or maxChars <= 0 then
        return ""
    end
    local pos, len, chars = 1, #value, 0
    while pos <= len and chars < maxChars do
        local b = byte(value, pos)
        if not b then
            break
        elseif b < 128 then
            pos = pos + 1
        elseif b < 224 then
            pos = pos + 2
        elseif b < 240 then
            pos = pos + 3
        else
            pos = pos + 4
        end
        chars = chars + 1
    end
    return sub(value, 1, pos - 1)
end

local function ResolveToTInlineSeparator(conf)
    local token = conf and conf.totInlineSeparator
    if token == "__CUSTOM__" then
        token = tostring(conf and conf.totInlineCustomSeparator or ""):gsub("[%c]", " ")
        token = Utf8Prefix(token, 5)
        if token == "" then
            token = " "
        end
    elseif token == nil then
        token = "|"
    else
        token = tostring(token)
    end
    if token == "" then
        token = " "
    end
    return " " .. token .. " "
end

local function ResolveToTInlineColorMode(value)
    value = tostring(value or "AUTO"):upper()
    if value == "TOT_NAME" or value == "TARGET_NAME" or value == "NPC" or value == "DEFAULT" then
        return value
    end
    return "AUTO"
end

local function ResolveToTInline(db, general, unit, targetText)
    if unit ~= "target" then
        targetText.inlineToT = nil
        return
    end

    local tot = type(db and db.targettarget) == "table" and db.targettarget or type(db and db.tot) == "table" and db.tot or nil
    if not (tot and tot.showToTInTargetName == true) then
        targetText.inlineToT = nil
        return
    end

    local inline = targetText.inlineToT
    if type(inline) ~= "table" then
        inline = {}
        targetText.inlineToT = inline
    end
    ResolveNameShortening(db, general, tot, "targettarget", inline)
    inline.enabled = true
    inline.unit = "targettarget"
    inline.separator = ResolveToTInlineSeparator(tot)
    inline.colorMode = ResolveToTInlineColorMode(tot.totInlineColorMode)
    inline.targetNameClassColor = targetText.nameClassColor == true
    inline.targetNameNpcColor = targetText.nameNpcColor == true
    inline.totNameClassColor, inline.totNameNpcColor = ResolveNameColorFlags(general, tot)
end

local function NormalizePortraitMode(conf)
    local mode = conf and conf.portraitMode
    if mode == "LEFT" or mode == "RIGHT" then
        return mode
    end
    if conf and conf.showPortrait == true then
        return "LEFT"
    end
    return "OFF"
end

local function NormalizePortraitRender(mode)
    return mode == "CLASS" and "CLASS" or "2D"
end

local function NormalizePortraitClassStyle(value)
    local fn = _G.MSUF_NormalizePortraitClassStyleValue
    if type(fn) == "function" then
        return fn(value)
    end
    local PM = MSUF and MSUF.PortraitMedia
    if PM and type(PM.NormalizeClassPack) == "function" then
        return PM.NormalizeClassPack(value)
    end
    if value == "RONDO_COLOR" or value == "RONDO_WOW" or value == "BLIZZARD" then
        return value
    end
    return "BLIZZARD"
end

local function NormalizePortraitShape(shape)
    if shape == "CIRCLE" or shape == "ROUNDED" or shape == "DIAMOND" then
        return shape
    end
    return "SQUARE"
end

local function NormalizePortraitBorder(style)
    if style == "SOLID" or style == "CLASS_COLOR" or style == "REACTION" or style == "CUSTOM" then
        return style
    end
    return "NONE"
end

local function NormalizeAlphaLayerMode(mode)
    if mode == true or mode == 1 or mode == "background" or mode == "backdrop" or mode == "bg" then
        return "background"
    elseif mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then
        return "health"
    end
    return "foreground"
end

local function CompileAlpha(out, conf, general, key)
    local alpha = out.alpha or {}
    out.alpha = alpha

    local legacyAlpha = conf.alpha or conf.frameAlpha or general.unitFrameAlpha
    local fallback = Clamp01(legacyAlpha, 1)
    local frameIn = Clamp01(conf.alphaInCombat, fallback)
    local frameOut = Clamp01(conf.alphaOutOfCombat, fallback)
    local sync = conf.alphaSyncBoth
    if sync == nil then
        sync = conf.alphaSync
    end
    if legacyAlpha ~= nil
        and (tonumber(conf.alphaInCombat) or 1) == 1
        and (tonumber(conf.alphaOutOfCombat) or 1) == 1 then
        frameIn = fallback
        frameOut = fallback
    end
    if sync then
        frameOut = frameIn
    end

    local layerMode = NormalizeAlphaLayerMode(conf.alphaLayerMode or general.alphaLayerMode)
    local layered = conf.alphaExcludeTextPortrait == true
    local fgIn = Clamp01(conf.alphaFGInCombat or general.alphaFGInCombat, frameIn)
    local fgOut = Clamp01(conf.alphaFGOutOfCombat or general.alphaFGOutOfCombat, frameOut)
    local bgIn = Clamp01(conf.alphaBGInCombat or general.alphaBGInCombat, frameIn)
    local bgOut = Clamp01(conf.alphaBGOutOfCombat or general.alphaBGOutOfCombat, frameOut)
    local hpIn = Clamp01(conf.alphaHPInCombat or general.alphaHPInCombat, fgIn)
    local hpOut = Clamp01(conf.alphaHPOutOfCombat or general.alphaHPOutOfCombat, fgOut)
    if sync then
        fgOut, bgOut, hpOut = fgIn, bgIn, hpIn
    end

    alpha.enabled = true
    alpha.inCombat = frameIn
    alpha.outCombat = frameOut
    alpha.layered = layered
    alpha.layerMode = layerMode
    alpha.foregroundInCombat = fgIn
    alpha.foregroundOutOfCombat = fgOut
    alpha.backgroundInCombat = bgIn
    alpha.backgroundOutOfCombat = bgOut
    alpha.healthInCombat = hpIn
    alpha.healthOutOfCombat = hpOut
    alpha.preserveHPColor = conf.alphaPreserveHPColor == true or general.alphaPreserveHPColor == true
    alpha.combatEvents = frameIn ~= frameOut
        or (layered and (fgIn ~= fgOut or bgIn ~= bgOut or hpIn ~= hpOut))
    alpha.opacityActive = frameIn ~= 1 or frameOut ~= 1
        or (layered and (fgIn ~= 1 or fgOut ~= 1 or bgIn ~= 1 or bgOut ~= 1 or hpIn ~= 1 or hpOut ~= 1))
    alpha.active = alpha.opacityActive == true
end

local function ClampStatusLayer(value, fallback)
    value = Number(value, fallback or 7)
    value = math.floor(value + 0.5)
    if value < 1 then
        return 1
    elseif value > 10 then
        return 10
    end
    return value
end

local function StatusBool(conf, general, key, fallback, legacyKey)
    local value = conf and conf[key]
    if value == nil and legacyKey then
        value = conf and conf[legacyKey]
    end
    if value == nil then
        value = general and general[key]
        if value == nil and legacyKey then
            value = general and general[legacyKey]
        end
    end
    return Bool(value, fallback)
end

local function StatusNumber(conf, general, key, fallback, legacyKey)
    local value = conf and conf[key]
    if value == nil and legacyKey then
        value = conf and conf[legacyKey]
    end
    if value == nil then
        value = general and general[key]
        if value == nil and legacyKey then
            value = general and general[legacyKey]
        end
    end
    return Number(value, fallback)
end

local function StatusString(conf, general, key, fallback, legacyKey)
    local value = conf and conf[key]
    if (type(value) ~= "string" or value == "") and legacyKey then
        value = conf and conf[legacyKey]
    end
    if type(value) ~= "string" or value == "" then
        value = general and general[key]
        if (type(value) ~= "string" or value == "") and legacyKey then
            value = general and general[legacyKey]
        end
    end
    if type(value) ~= "string" or value == "" then
        value = fallback
    end
    return value or ""
end

local function StatusAllowed(key, id)
    if id == "leader" or id == "combat" or id == "incomingRes" then
        return key == "player" or key == "target"
    elseif id == "resting" then
        return key == "player"
    elseif id == "raidGroup" then
        return key == "player" or key == "target" or key == "targettarget" or key == "focustarget" or key == "focus"
    elseif id == "elite" then
        return key == "target" or key == "focus" or key == "targettarget" or key == "focustarget" or key == "boss"
    end
    return true
end

local function ResetList(list)
    list = list or {}
    wipe(list)
    return list
end

local function AddEvent(list, event)
    list[#list + 1] = event
end

local function CompileStatusEntry(status, id, conf, general, key, showKey, fallbackShow, sizeKey, fallbackSize, anchorKey, fallbackAnchor, xKey, fallbackX, yKey, fallbackY, layerKey, fallbackLayer)
    local entry = status[id] or {}
    status[id] = entry
    entry.enabled = StatusAllowed(key, id) and StatusBool(conf, general, showKey, fallbackShow) or false
    entry.size = StatusNumber(conf, general, sizeKey, fallbackSize)
    entry.anchor = StatusString(conf, general, anchorKey, fallbackAnchor)
    entry.x = StatusNumber(conf, general, xKey, fallbackX)
    entry.y = StatusNumber(conf, general, yKey, fallbackY)
    entry.layer = ClampStatusLayer(StatusNumber(conf, general, layerKey, fallbackLayer), fallbackLayer)
    return entry
end

local function CompileLoadConditions(out, conf)
    local load = out.load or {}
    out.load = load
    load.hideMounted = Bool(conf.loadCondHideMounted, false)
    load.hideOutOfCombat = Bool(conf.loadCondHideOutOfCombat, false)
    load.hideSolo = Bool(conf.loadCondHideSolo, false)
    load.hideInVehicle = Bool(conf.loadCondHideInVehicle, false)
    load.hideInGroup = Bool(conf.loadCondHideInGroup, false)
    load.hideInInstance = Bool(conf.loadCondHideInInstance, false)
    load.hideResting = Bool(conf.loadCondHideResting, false)
    load.hideInCombat = Bool(conf.loadCondHideInCombat, false)
    load.hideStealthed = Bool(conf.loadCondHideStealthed, false)
    load.active = load.hideMounted == true
        or load.hideOutOfCombat == true
        or load.hideSolo == true
        or load.hideInVehicle == true
        or load.hideInGroup == true
        or load.hideInInstance == true
        or load.hideResting == true
        or load.hideInCombat == true
        or load.hideStealthed == true

    load.unitlessEvents = ResetList(load.unitlessEvents)
    if load.active then
        AddEvent(load.unitlessEvents, "PLAYER_REGEN_ENABLED")
    end
    if load.hideInInstance == true then
        AddEvent(load.unitlessEvents, "PLAYER_ENTERING_WORLD")
        AddEvent(load.unitlessEvents, "ZONE_CHANGED_NEW_AREA")
    end
end

local function TextureFromGlobal()
    local fn = _G.MSUF_GetBarTexture
    if type(fn) == "function" then
        return fn() or WHITE
    end
    return WHITE
end

local function BackgroundTextureFromGlobal()
    local fn = _G.MSUF_GetBarBackgroundTexture
    if type(fn) == "function" then
        return fn() or WHITE
    end
    return WHITE
end

local function ClassPowerFallbackWidth(out, bars)
    local widthMode = bars and bars.classPowerWidthMode or "player"
    if widthMode == "custom" then
        local custom = Number(bars and bars.classPowerWidth, 0)
        if custom >= 30 then
            return custom
        end
    end
    return max(1, Number(out and out.width, 275) - 4)
end

local function CooldownWidthFrameName(mode)
    return CDM_WIDTH_FRAMES[mode]
end

local function FontFromGlobal()
    local fn = _G.MSUF_GetFontPath
    if type(fn) == "function" then
        return fn() or DEFAULT_FONT
    end
    return DEFAULT_FONT
end

local function FontFlagsFromGlobal()
    local fn = _G.MSUF_GetFontFlags
    if type(fn) == "function" then
        return fn() or "OUTLINE"
    end
    return "OUTLINE"
end

local function BossLayoutDelta(conf, index, def)
    conf = conf or {}
    def = def or DEFAULTS.boss
    index = Number(index, 1)
    local step = index - 1
    if step <= 0 then
        return 0, 0
    end
    local spacing = Number(conf.spacing, -42)
    local mode = conf.bossLayoutMode or "VERTICAL_DOWN"
    if mode == "VERTICAL_UP" then
        return 0, step * -spacing
    elseif mode == "HORIZONTAL_RIGHT" or mode == "HORIZONTAL_LEFT" then
        local width = Number(conf.width or conf.frameWidth, def.width)
        local height = Number(conf.height or conf.frameHeight, def.height)
        local visualGap = abs(spacing) - height
        local delta = step * (width + max(0, visualGap))
        if mode == "HORIZONTAL_LEFT" then
            delta = -delta
        end
        return delta, 0
    end
    return 0, step * spacing
end

local function BossOffset(conf, index, def)
    local x = Number(conf.offsetX or conf.x, def.x)
    local y = Number(conf.offsetY or conf.y, def.y)
    local dx, dy = BossLayoutDelta(conf, index, def)
    return x + dx, y + dy
end

local function PowerEnabled(unit, key, conf, bars)
    if conf.showPowerBar ~= nil then
        return conf.showPowerBar ~= false
    end
    local powerKey = POWER_KEYS[key]
    if powerKey and bars and bars[powerKey] ~= nil then
        return bars[powerKey] ~= false
    end
    if conf.showPowerText == nil and conf.showPower ~= nil then
        return conf.showPower ~= false
    end
    return DEFAULTS[key] and DEFAULTS[key].showPower ~= false
end

local function CastbarEnabled(unit, key, general)
    local shouldUseGlobal = _G.MSUF_ShouldUseMSUFCastbar
    if type(shouldUseGlobal) == "function" then
        return shouldUseGlobal(unit, general) == true
    end
    local shouldUse = UF.ShouldUseMSUFCastbar
    if type(shouldUse) == "function" then
        return shouldUse(unit) == true
    end
    local castbarKey = CASTBAR_KEYS[key]
    if not castbarKey then
        return false
    end
    return not (general and general[castbarKey] == false)
end

local function ResolveAnchorSettings(conf, general)
    local anchorFrameName = conf and conf.anchorFrameName
    if type(anchorFrameName) == "string" and anchorFrameName ~= "" then
        return anchorFrameName, conf.anchorToUnitframe, IsCooldownViewerFrameName(anchorFrameName)
    end

    local anchorToUnitframe = conf and conf.anchorToUnitframe
    if type(anchorToUnitframe) == "string"
        and anchorToUnitframe ~= ""
        and anchorToUnitframe ~= "GLOBAL"
        and anchorToUnitframe ~= "global"
        and anchorToUnitframe ~= "FREE" then
        if IsCooldownViewerFrameName(anchorToUnitframe) then
            return anchorToUnitframe, "GLOBAL", true
        end
        return nil, anchorToUnitframe, false
    end

    if general and general.anchorToCooldown == true then
        return "EssentialCooldownViewer", "GLOBAL", true
    end

    local globalAnchor = general and general.anchorName
    if IsCooldownViewerFrameName(globalAnchor) then
        return globalAnchor, "GLOBAL", true
    end
    if type(globalAnchor) == "string"
        and globalAnchor ~= ""
        and globalAnchor ~= "UIParent"
        and globalAnchor ~= "WorldFrame"
        and globalAnchor ~= "EssentialCooldownViewer" then
        return globalAnchor, "GLOBAL", false
    end

    return nil, anchorToUnitframe, false
end

local function ResolveUnit(db, unit, out)
    out = out or {}
    wipe(out)

    local key = UF.ConfigKeyForUnit(unit)
    local def = DEFAULTS[key] or DEFAULTS.player
    local conf = type(db[key]) == "table" and db[key] or {}
    if key == "targettarget" and type(db.targettarget) ~= "table" and type(db.tot) == "table" then
        conf = db.tot
    end
    local general = type(db.general) == "table" and db.general or {}
    local bars = type(db.bars) == "table" and db.bars or {}
    local bossIndex = unit and unit:match("^boss(%d+)$")

    out.unit = unit
    out.key = key
    out.enabled = conf.enabled ~= false
    out.width = Number(conf.width or conf.frameWidth, def.width)
    out.height = Number(conf.height or conf.frameHeight, def.height)
    local globalCooldownAnchor
    out.anchorFrameName, out.anchorToUnitframe, globalCooldownAnchor = ResolveAnchorSettings(conf, general)
    local ecvRule = globalCooldownAnchor and ECV_ANCHORS[key] or nil
    if ecvRule then
        out.point = ecvRule[1]
        out.relativePoint = ecvRule[2]
    else
        out.point = conf.point or "CENTER"
        out.relativePoint = conf.relativePoint or out.point
    end
    local x, y
    if bossIndex then
        x, y = BossOffset(conf, tonumber(bossIndex) or 1, def)
    else
        x = Number(conf.offsetX or conf.x, def.x)
        y = Number(conf.offsetY or conf.y, def.y)
    end
    if ecvRule then
        x = x + Number(ecvRule[3], 0)
        y = y + Number(ecvRule[4], 0)
    end
    out.x, out.y = x, y

    out.texture = TextureFromGlobal()
    out.backgroundTexture = BackgroundTextureFromGlobal()
    out.backgroundAlpha = ResolveBgAlpha(general, bars)
    if conf.showName ~= nil then
        out.showName = conf.showName == true
    else
        out.showName = def.showName ~= false
    end
    out.showHealthText = conf.showHP ~= false and conf.showHPText ~= false
    if conf.showPowerText ~= nil then
        out.showPowerText = conf.showPowerText ~= false
    elseif conf.showPower ~= nil then
        out.showPowerText = conf.showPower ~= false
    else
        out.showPowerText = true
    end
    out.font = FontFromGlobal()
    out.fontFlags = FontFlagsFromGlobal()
    out.fontSize = Number(conf.fontSize or general.fontSize, 12)
    out.nameFontSize = Number(conf.nameFontSize or general.nameFontSize, out.fontSize)
    out.healthFontSize = Number(conf.hpFontSize or general.hpFontSize, out.fontSize)
    out.powerFontSize = Number(conf.powerFontSize or general.powerFontSize, out.fontSize)
    out.textColor = out.textColor or {}
    ResolveTextColor(general, out.textColor)

    out.text = out.text or {}
    out.text.healthLeft = NormalizeHealthTextMode(conf.textLeft, "NONE")
    out.text.healthCenter = NormalizeHealthTextMode(conf.textCenter, "NONE")
    out.text.healthRight = NormalizeHealthTextMode(conf.textRight or conf.hpTextMode or general.hpTextMode, "CURPERCENT")
    if conf.hpTextReverse ~= nil then
        out.text.healthReverse = conf.hpTextReverse == true
    else
        out.text.healthReverse = general.hpTextReverse == true
    end
    out.text.healthDelimiter = conf.hpTextSeparator or general.hpTextSeparator or " - "
    out.text.nameAnchor = conf.nameTextAnchor or conf.nameAnchor or general.nameTextAnchor or general.nameAnchor or "LEFT"
    out.text.nameX = Number(conf.nameOffsetX or conf.nameTextOffsetX or general.nameOffsetX or general.nameTextOffsetX, 4)
    out.text.nameY = Number(conf.nameOffsetY or conf.nameTextOffsetY or general.nameOffsetY or general.nameTextOffsetY, -4)
    out.text.healthX = Number(conf.hpOffsetX or conf.hpTextOffsetX or general.hpOffsetX or general.hpTextOffsetX, -4)
    out.text.healthY = Number(conf.hpOffsetY or conf.hpTextOffsetY or general.hpOffsetY or general.hpTextOffsetY, -4)
    out.text.healthLeftX = out.text.healthX + Number(conf.hpTextLeftOffsetX or conf.hpLeftOffsetX or general.hpTextLeftOffsetX or general.hpLeftOffsetX, 0)
    out.text.healthLeftY = out.text.healthY + Number(conf.hpTextLeftOffsetY or conf.hpLeftOffsetY or general.hpTextLeftOffsetY or general.hpLeftOffsetY, 0)
    out.text.healthCenterX = out.text.healthX + Number(conf.hpTextCenterOffsetX or conf.hpCenterOffsetX or general.hpTextCenterOffsetX or general.hpCenterOffsetX, 0)
    out.text.healthCenterY = out.text.healthY + Number(conf.hpTextCenterOffsetY or conf.hpCenterOffsetY or general.hpTextCenterOffsetY or general.hpCenterOffsetY, 0)
    out.text.healthRightX = out.text.healthX + Number(conf.hpTextRightOffsetX or conf.hpRightOffsetX or general.hpTextRightOffsetX or general.hpRightOffsetX, 0)
    out.text.healthRightY = out.text.healthY + Number(conf.hpTextRightOffsetY or conf.hpRightOffsetY or general.hpTextRightOffsetY or general.hpRightOffsetY, 0)
    out.text.powerLeft = NormalizePowerTextMode(conf.powerTextLeft, "NONE")
    out.text.powerCenter = NormalizePowerTextMode(conf.powerTextCenter, "NONE")
    out.text.powerRight = NormalizePowerTextMode(conf.powerTextRight or conf.powerTextMode or general.powerTextMode, "CURPERCENT")
    out.text.powerDelimiter = conf.powerTextSeparator or general.powerTextSeparator or out.text.healthDelimiter
    out.text.powerX = Number(conf.powerOffsetX or conf.powerTextOffsetX or general.powerOffsetX or general.powerTextOffsetX, -4)
    out.text.powerY = Number(conf.powerOffsetY or conf.powerTextOffsetY or general.powerOffsetY or general.powerTextOffsetY, 4)
    out.text.powerLeftX = out.text.powerX + Number(conf.powerTextLeftOffsetX or conf.powerLeftOffsetX or general.powerTextLeftOffsetX or general.powerLeftOffsetX, 0)
    out.text.powerLeftY = out.text.powerY + Number(conf.powerTextLeftOffsetY or conf.powerLeftOffsetY or general.powerTextLeftOffsetY or general.powerLeftOffsetY, 0)
    out.text.powerCenterX = out.text.powerX + Number(conf.powerTextCenterOffsetX or conf.powerCenterOffsetX or general.powerTextCenterOffsetX or general.powerCenterOffsetX, 0)
    out.text.powerCenterY = out.text.powerY + Number(conf.powerTextCenterOffsetY or conf.powerCenterOffsetY or general.powerTextCenterOffsetY or general.powerCenterOffsetY, 0)
    out.text.powerRightX = out.text.powerX + Number(conf.powerTextRightOffsetX or conf.powerRightOffsetX or general.powerTextRightOffsetX or general.powerRightOffsetX, 0)
    out.text.powerRightY = out.text.powerY + Number(conf.powerTextRightOffsetY or conf.powerRightOffsetY or general.powerTextRightOffsetY or general.powerRightOffsetY, 0)
    out.text.nameLayer = Number(conf.nameTextLayer or general.nameTextLayer, 5)
    out.text.healthLayer = Number(conf.hpTextLayer or conf.textLayer or general.hpTextLayer or general.textLayer, 5)
    out.text.powerLayer = Number(conf.powerTextLayer or general.powerTextLayer, 2)
    ResolveNameShortening(db, general, conf, unit, out.text)
    out.text.nameClassColor, out.text.nameNpcColor = ResolveNameColorFlags(general, conf)
    out.text.npcColorMode = general.npcColorMode == "type" and "type" or "reaction"
    out.text.npcTypeColorText = general.npcTypeColorText ~= false
    out.text.npcTypeTarget = general.npcTypeTarget ~= false
    out.text.npcTypeFocus = general.npcTypeFocus ~= false
    out.text.npcTypeBoss = general.npcTypeBoss ~= false
    out.text.npcTypeToT = general.npcTypeToT ~= false
    ResolveToTInline(db, general, unit, out.text)
    out.text.powerColorByType = general.colorPowerTextByType == true
    out.text.shortNumbers = general.useShortNumbers ~= false
    out.text.hidePercentSymbol = general.hidePercentSymbol == true
    local healthThrottle = Number(conf.hpTextThrottleMs or conf.healthTextThrottleMs or general.hpTextThrottleMs or general.healthTextThrottleMs, nil)
    if healthThrottle ~= nil then
        healthThrottle = healthThrottle / 1000
    else
        healthThrottle = Number(conf.hpTextThrottle or conf.healthTextThrottle or general.hpTextThrottle or general.healthTextThrottle, 0.10)
        if healthThrottle > 10 then
            healthThrottle = healthThrottle / 1000
        end
    end
    if conf.hpTextThrottleEnabled == false or conf.healthTextThrottleEnabled == false or general.hpTextThrottleEnabled == false or general.healthTextThrottleEnabled == false then
        healthThrottle = 0
    elseif healthThrottle < 0 then
        healthThrottle = 0
    elseif healthThrottle > 1 then
        healthThrottle = 1
    end
    out.text.healthThrottle = healthThrottle
    local powerThrottle = Number(conf.powerTextThrottleMs or general.powerTextThrottleMs, nil)
    if powerThrottle ~= nil then
        powerThrottle = powerThrottle / 1000
    else
        powerThrottle = Number(conf.powerTextThrottle or general.powerTextThrottle, key == "player" and 0.05 or 0.10)
        if powerThrottle > 10 then
            powerThrottle = powerThrottle / 1000
        end
    end
    if conf.powerTextThrottleEnabled == false or general.powerTextThrottleEnabled == false then
        powerThrottle = 0
    elseif powerThrottle < 0 then
        powerThrottle = 0
    elseif powerThrottle > 1 then
        powerThrottle = 1
    end
    out.text.powerThrottle = powerThrottle

    out.health = out.health or {}
    out.health.texture = out.texture
    out.health.backgroundTexture = out.backgroundTexture
    out.health.reverse = conf.reverseFillBars == true
    out.health.smooth = conf.smoothFill ~= false
    out.health.mode = ResolveBarMode(general)
    out.health.gradient = general.enableHealthGradient ~= false
    out.health.npcColorMode = general.npcColorMode == "type" and "type" or "reaction"
    out.health.npcTypeColorBar = general.npcTypeColorBar ~= false
    out.health.npcTypeTarget = general.npcTypeTarget ~= false
    out.health.npcTypeFocus = general.npcTypeFocus ~= false
    out.health.npcTypeBoss = general.npcTypeBoss ~= false
    out.health.npcTypeToT = general.npcTypeToT ~= false
    out.health.petColorEnabled = general.petFrameColorEnabled == true
    out.health.petR = Number(general.petFrameColorR, 0)
    out.health.petG = Number(general.petFrameColorG, 0.8)
    out.health.petB = Number(general.petFrameColorB, 0)
    if out.health.mode == "unified" then
        CopyColor(out.health, general.unifiedBarR or 0.1, general.unifiedBarG or 0.6, general.unifiedBarB or 0.9, 1)
    elseif out.health.mode == "dark" then
        ResolveDarkColor(general, out.health)
    else
        CopyColor(out.health, general.unifiedBarR or 0.1, general.unifiedBarG or 0.6, general.unifiedBarB or 0.9, 1)
    end
    out.health.background = ResolveHealthBackground(general, bars, out.health, out.health.background or {})
    out.health.backgroundMatchHealth = general.barBgMatchHPColor == true

    out.power = out.power or {}
    out.power.enabled = PowerEnabled(unit, key, conf, bars)
    out.power.height = Number(conf.powerBarHeight or bars.powerBarHeight, 3)
    out.power.texture = out.texture
    out.power.backgroundTexture = out.backgroundTexture
    out.power.frequent = unit == "player" and bars.realtimePowerText == true
    out.power.mode = ResolvePowerMode(general)
    out.power.colors = out.power.colors or {}
    wipe(out.power.colors)
    local powerOverrides = type(general.powerColorOverrides) == "table" and general.powerColorOverrides or nil
    if powerOverrides then
        for token, color in pairs(powerOverrides) do
            if type(color) == "table" then
                local r = tonumber(color.r or color[1])
                local g = tonumber(color.g or color[2])
                local b = tonumber(color.b or color[3])
                if r and g and b then
                    out.power.colors[token] = { r = r, g = g, b = b }
                end
            end
        end
    end
    local classPowerOverrides = type(general.classPowerColorOverrides) == "table" and general.classPowerColorOverrides or nil
    if classPowerOverrides then
        for token, color in pairs(classPowerOverrides) do
            if out.power.colors[token] == nil and type(color) == "table" then
                local r = tonumber(color.r or color[1])
                local g = tonumber(color.g or color[2])
                local b = tonumber(color.b or color[3])
                if r and g and b then
                    out.power.colors[token] = { r = r, g = g, b = b }
                end
            end
        end
    end
    if conf.embedPowerBarIntoHealth ~= nil then
        out.power.embed = conf.embedPowerBarIntoHealth == true
    elseif bars.embedPowerBarIntoHealth ~= nil then
        out.power.embed = bars.embedPowerBarIntoHealth == true
    else
        out.power.embed = true
    end
    out.power.detached = conf.powerBarDetached == true
    out.power.detachedWidth = Number(conf.detachedPowerBarWidth, out.width)
    out.power.detachedHeight = Number(conf.detachedPowerBarHeight, out.power.height)
    out.power.detachedX = Number(conf.detachedPowerBarOffsetX, 0)
    out.power.detachedY = Number(conf.detachedPowerBarOffsetY, -4)
    out.power.detachedLevel = Number(conf.detachedPowerBarFrameLevelOffset, 6)
    out.power.textOnDetached = conf.detachedPowerBarTextOnBar == true
    out.power.detachedSyncClass = key == "player" and conf.detachedPowerBarSyncClassPower ~= false
    out.power.detachedAnchorClass = key == "player" and conf.detachedPowerBarAnchorToClassPower == true
    out.power.detachedClassWidth = ClassPowerFallbackWidth(out, bars)
    out.power.detachedClassWidthFrameName = CooldownWidthFrameName(bars.classPowerWidthMode)
    out.power.detachedWidthFrameName = CooldownWidthFrameName(bars.detachedPowerBarWidthMode)
    out.power.borderEnabled = Bool(conf.powerBarBorderEnabled, bars.powerBarBorderEnabled == true)
    out.power.borderThickness = Number(conf.powerBarBorderThickness or bars.powerBarBorderThickness or bars.powerBarBorderSize, 1)
    if out.power.borderThickness < 0 then
        out.power.borderThickness = 0
    elseif out.power.borderThickness > 10 then
        out.power.borderThickness = 10
    end
    out.power.borderR = Number(general.barOutlineColorR or general.barBorderR, 0)
    out.power.borderG = Number(general.barOutlineColorG or general.barBorderG, 0)
    out.power.borderB = Number(general.barOutlineColorB or general.barBorderB, 0)
    out.power.borderA = Number(general.barOutlineColorA or general.barBorderA, 1)
    if out.power.mode == "unified" then
        CopyColor(out.power, general.unifiedBarR or 0.1, general.unifiedBarG or 0.6, general.unifiedBarB or 0.9, 1)
    elseif out.power.mode == "dark" then
        ResolveDarkColor(general, out.power)
    elseif out.power.mode == "static" then
        CopyColor(out.power, general.powerBarColorR or 0.1, general.powerBarColorG or 0.35, general.powerBarColorB or 0.95, 1)
    else
        CopyColor(out.power, 0.1, 0.35, 0.95, 1)
    end
    out.power.background = ResolvePowerBackground(general, bars, out.health, out.power.background or {})
    out.power.backgroundMatchHealth = general.powerBarBgMatchBarColor == true or bars.powerBarBgMatchBarColor == true
    out.power.reverse = out.health.reverse == true
    if conf.powerSmoothFill ~= nil then
        out.power.smooth = conf.powerSmoothFill == true
    else
        out.power.smooth = unit == "player" and bars.smoothPowerBar ~= false or false
    end

    out.prediction = out.prediction or {}
    local absorbMode = Number(ScopedValue(conf, general, "absorbTextMode", nil), nil)
    if absorbMode then
        out.prediction.absorb = absorbMode == 2 or absorbMode == 3
    else
        out.prediction.absorb = ScopedValue(conf, general, "enableAbsorbBar", true) ~= false
    end
    out.prediction.heal = general.showSelfHealPrediction == true or general.enableHealPrediction == true
    out.prediction.healAbsorb = out.prediction.absorb == true and ScopedValue(conf, general, "healAbsorbEnabled", true) ~= false
    out.prediction.test = AbsorbTestEnabledForKey(key)
    if out.prediction.test == true then
        out.prediction.absorb = true
        out.prediction.heal = true
        out.prediction.healAbsorb = true
    end
    out.prediction.enabled = out.prediction.heal == true or out.prediction.absorb == true or out.prediction.healAbsorb == true
    out.prediction.texture = out.texture
    out.prediction.healAnchorMode = Number(ScopedValue(conf, general, "healPredAnchorMode", 3), 3)
    out.prediction.absorbAnchorMode = Number(ScopedValue(conf, general, "absorbAnchorMode", 2), 2)
    out.prediction.absorbTexture = ScopedValue(conf, general, "absorbBarTexture", nil)
    out.prediction.healAbsorbTexture = ScopedValue(conf, general, "healAbsorbBarTexture", nil)
    out.prediction.healR = Number(general.healPredictionColorR, 0)
    out.prediction.healG = Number(general.healPredictionColorG, 1)
    out.prediction.healB = Number(general.healPredictionColorB, 0)
    out.prediction.healA = Number(general.healPredictionColorA, 0.45)
    out.prediction.absorbR = Number(general.absorbBarColorR, 1)
    out.prediction.absorbG = Number(general.absorbBarColorG, 1)
    out.prediction.absorbB = Number(general.absorbBarColorB, 1)
    out.prediction.absorbA = Number(ScopedValue(conf, general, "absorbBarOpacity", general.absorbBarColorA), 0.75)
    out.prediction.healAbsorbR = Number(general.healAbsorbBarColorR, 0.7)
    out.prediction.healAbsorbG = Number(general.healAbsorbBarColorG, 0)
    out.prediction.healAbsorbB = Number(general.healAbsorbBarColorB, 0)
    out.prediction.healAbsorbA = Number(ScopedValue(conf, general, "healAbsorbBarOpacity", general.healAbsorbBarColorA), 1)

    CompileAlpha(out, conf, general, key)

    CompileLoadConditions(out, conf)

    out.dispel = out.dispel or {}
    local dispelColorMode = ScopedValue(conf, general, "hlDispelColorMode", "SINGLE")
    out.dispel.colorMode = dispelColorMode == "TYPE" and "TYPE" or "SINGLE"
    out.dispel.r = Number(ScopedValue(conf, general, "hlDispelColorR", general.dispelBorderColorR), 0.25)
    out.dispel.g = Number(ScopedValue(conf, general, "hlDispelColorG", general.dispelBorderColorG), 0.75)
    out.dispel.b = Number(ScopedValue(conf, general, "hlDispelColorB", general.dispelBorderColorB), 1)
    out.dispel.a = 1
    out.dispel.typeMagicR = Number(general.dispelTypeMagicR, 0.20)
    out.dispel.typeMagicG = Number(general.dispelTypeMagicG, 0.60)
    out.dispel.typeMagicB = Number(general.dispelTypeMagicB, 1.00)
    out.dispel.typeCurseR = Number(general.dispelTypeCurseR, 0.60)
    out.dispel.typeCurseG = Number(general.dispelTypeCurseG, 0.00)
    out.dispel.typeCurseB = Number(general.dispelTypeCurseB, 1.00)
    out.dispel.typeDiseaseR = Number(general.dispelTypeDiseaseR, 0.60)
    out.dispel.typeDiseaseG = Number(general.dispelTypeDiseaseG, 0.40)
    out.dispel.typeDiseaseB = Number(general.dispelTypeDiseaseB, 0.00)
    out.dispel.typePoisonR = Number(general.dispelTypePoisonR, 0.00)
    out.dispel.typePoisonG = Number(general.dispelTypePoisonG, 0.60)
    out.dispel.typePoisonB = Number(general.dispelTypePoisonB, 0.00)
    out.dispel.typeBleedR = Number(general.dispelTypeBleedR, 0.80)
    out.dispel.typeBleedG = Number(general.dispelTypeBleedG, 0.10)
    out.dispel.typeBleedB = Number(general.dispelTypeBleedB, 0.10)
    out.dispelOverlay = out.dispelOverlay or {}
    out.dispelOverlay.enabled = ScopedValue(conf, general, "unitDispelOverlayEnabled", false) == true
    out.dispelOverlay.trigger = NormalizeDispelOverlayTrigger(ScopedValue(conf, general, "unitDispelOverlayTrigger", "BORDER"))
    out.dispelOverlay.style = NormalizeDispelOverlayStyle(ScopedValue(conf, general, "unitDispelOverlayStyle", "FULL"))
    out.dispelOverlay.onHealth = ScopedValue(conf, general, "unitDispelOverlayOnHealth", true) ~= false
    out.dispelOverlay.alpha = Clamp01(ScopedValue(conf, general, "unitDispelOverlayAlpha", 0.35), 0.35)

    out.border = out.border or {}
    local outlineThickness = conf.hlOverride == true and conf.barOutlineThickness ~= nil and conf.barOutlineThickness or bars.barOutlineThickness
    if outlineThickness == nil then
        outlineThickness = general.useBarBorder == false and 0 or 1
    end
    out.border.thickness = Number(outlineThickness, 1)
    out.border.enabled = bars.showBarBorder ~= false and out.border.thickness > 0
    out.border.r = Number(general.barOutlineColorR or general.barBorderR, 0)
    out.border.g = Number(general.barOutlineColorG or general.barBorderG, 0)
    out.border.b = Number(general.barOutlineColorB or general.barBorderB, 0)
    out.border.a = Number(general.barOutlineColorA or general.barBorderA, 1)
    out.border.highlightThickness = Number(ScopedValue(conf, general, "highlightBorderThickness", bars.highlightBorderThickness or general.highlightBorderThickness), out.border.thickness)
    out.border.aggroR = Number(ScopedValue(conf, general, "hlAggroColorR", general.aggroBorderColorR or general.aggroBorderR), 1.00)
    out.border.aggroG = Number(ScopedValue(conf, general, "hlAggroColorG", general.aggroBorderColorG or general.aggroBorderG), 0.55)
    out.border.aggroB = Number(ScopedValue(conf, general, "hlAggroColorB", general.aggroBorderColorB or general.aggroBorderB), 0.00)
    out.border.purgeR = Number(ScopedValue(conf, general, "hlPurgeColorR", general.purgeBorderColorR), 1.00)
    out.border.purgeG = Number(ScopedValue(conf, general, "hlPurgeColorG", general.purgeBorderColorG), 0.85)
    out.border.purgeB = Number(ScopedValue(conf, general, "hlPurgeColorB", general.purgeBorderColorB), 0.00)
    local bossColor = general.bossTargetHighlightColor
    out.border.bossTargetR = Number(type(bossColor) == "table" and bossColor[1], 1.00)
    out.border.bossTargetG = Number(type(bossColor) == "table" and bossColor[2], 0.82)
    out.border.bossTargetB = Number(type(bossColor) == "table" and bossColor[3], 0.00)
    local legacyDispelBorder = general.dispelBorderEnabled == true or general.hlDispelBorderEnabled == true
    if general.dispelBorderEnabled == nil and general.hlDispelBorderEnabled == nil then
        legacyDispelBorder = true
    end
    out.border.aggro = OutlineModeEnabled(ScopedValue(conf, general, "aggroOutlineMode", nil),
        general.aggroIndicatorMode == "border" or general.enableAggroHighlight == true)
    out.border.dispel = OutlineModeEnabled(ScopedValue(conf, general, "dispelOutlineMode", nil),
        legacyDispelBorder)
    out.border.dispelTrigger = NormalizeDispelDetectTrigger(ScopedValue(conf, general, "dispelBorderTrigger", "BY_ME"))
    out.border.purge = OutlineModeEnabled(ScopedValue(conf, general, "purgeOutlineMode", nil),
        general.purgeBorderEnabled == true or general.hlPurgeBorderEnabled == true)

    out.portrait = out.portrait or {}
    local portraitMode = NormalizePortraitMode(conf)
    local portraitOverride = Number(conf.portraitSizeOverride, Number(conf.portraitSize, 0))
    local portraitAutoSize = max(16, Number(out.height, 30) - 4)
    local portraitSize = portraitOverride > 0 and max(16, portraitOverride) or portraitAutoSize
    out.portrait.enabled = portraitMode ~= "OFF"
    out.portrait.side = portraitMode == "RIGHT" and "RIGHT" or "LEFT"
    out.portrait.render = NormalizePortraitRender(conf.portraitRender)
    out.portrait.classStyle = NormalizePortraitClassStyle(conf.portraitClassStyle)
    out.portrait.shape = NormalizePortraitShape(conf.portraitShape)
    out.portrait.size = portraitSize
    out.portrait.x = Number(conf.portraitOffsetX, 0)
    out.portrait.y = Number(conf.portraitOffsetY, 0)
    out.portrait.border = out.portrait.border or {}
    out.portrait.border.style = NormalizePortraitBorder(conf.portraitBorderStyle)
    out.portrait.border.thickness = max(1, Number(conf.portraitBorderThickness, 2))
    out.portrait.border.fill = conf.portraitFillBorder == true
    out.portrait.border.r = Number(general.portraitBorderColorR, 1)
    out.portrait.border.g = Number(general.portraitBorderColorG, 1)
    out.portrait.border.b = Number(general.portraitBorderColorB, 1)
    out.portrait.border.a = Number(general.portraitBorderColorA, 1)
    out.portrait.bg = out.portrait.bg or {}
    out.portrait.bg.enabled = conf.portraitBgEnabled == true
    out.portrait.bg.r = Number(general.portraitBgColorR, 0.05)
    out.portrait.bg.g = Number(general.portraitBgColorG, 0.05)
    out.portrait.bg.b = Number(general.portraitBgColorB, 0.05)
    out.portrait.bg.a = Number(general.portraitBgColorA, 0.85)

    out.status = out.status or {}
    local status = out.status
    status.key = key
    local statusAlpha = StatusNumber(conf, general, "stateIconsAlpha", 1, "statusIconsAlpha")
    if statusAlpha > 1 then
        statusAlpha = statusAlpha / 100
    end
    status.alpha = Clamp01(statusAlpha, 1)
    status.testMode = StatusBool(conf, general, "stateIconsTestMode", false, "statusIconsTestMode")
    status.useMidnight = StatusBool(conf, general, "statusIconsUseMidnightStyle", false)

    local leader = CompileStatusEntry(status, "leader", conf, general, key, "showLeaderIcon", true, "leaderIconSize", 14, "leaderIconAnchor", "TOPLEFT", "leaderIconOffsetX", 0, "leaderIconOffsetY", 3, "leaderIconLayer", 7)
    leader.style = StatusString(conf, general, "leaderIconStyle", "BLIZZARD")

    CompileStatusEntry(status, "raidMarker", conf, general, key, "showRaidMarker", true, "raidMarkerSize", 18, "raidMarkerAnchor", "TOPLEFT", "raidMarkerOffsetX", 16, "raidMarkerOffsetY", 3, "raidMarkerLayer", 7)
    CompileStatusEntry(status, "level", conf, general, key, "showLevelIndicator", true, "levelIndicatorSize", Number(conf.nameFontSize or general.nameFontSize, out.nameFontSize), "levelIndicatorAnchor", "NAMERIGHT", "levelIndicatorOffsetX", 0, "levelIndicatorOffsetY", 0, "levelIndicatorLayer", 7)
    local raidGroup = CompileStatusEntry(status, "raidGroup", conf, general, key, "showRaidGroupInName", false, "nameFontSize", out.nameFontSize, "raidGroupNameAnchor", "NAMERIGHT", "raidGroupNameOffsetX", 3, "raidGroupNameOffsetY", 0, "nameTextLayer", 5)
    raidGroup.style = StatusString(conf, general, "raidGroupNameStyle", "PAREN")
    CompileStatusEntry(status, "elite", conf, general, key, "showEliteIcon", true, "eliteIconSize", 20, "eliteIconAnchor", "TOPRIGHT", "eliteIconOffsetX", 2, "eliteIconOffsetY", 2, "eliteIconLayer", 7)
    local statusText = CompileStatusEntry(status, "statusText", conf, general, key, "statusTextEnabled", true, "statusTextSize", out.nameFontSize + 2, "statusTextAnchor", "CENTER", "statusTextOffsetX", 0, "statusTextOffsetY", 0, "statusTextLayer", 7)
    local statusIndicators = type(general.statusIndicators) == "table" and general.statusIndicators or nil
    statusText.showAFK = statusIndicators == nil or statusIndicators.showAFK ~= false
    statusText.showDND = statusIndicators == nil or statusIndicators.showDND ~= false
    statusText.showDead = statusIndicators == nil or statusIndicators.showDead ~= false
    statusText.showGhost = statusIndicators == nil or statusIndicators.showGhost ~= false
    local combat = CompileStatusEntry(status, "combat", conf, general, key, "showCombatStateIndicator", true, "combatStateIndicatorSize", 18, "combatStateIndicatorAnchor", "TOPLEFT", "combatStateIndicatorOffsetX", 0, "combatStateIndicatorOffsetY", 0, "combatStateIndicatorLayer", 7)
    combat.symbol = StatusString(conf, general, "combatStateIndicatorSymbol", "DEFAULT")
    local resting = CompileStatusEntry(status, "resting", conf, general, key, "showRestingIndicator", false, "restedStateIndicatorSize", 18, "restedStateIndicatorAnchor", "TOPLEFT", "restedStateIndicatorOffsetX", 0, "restedStateIndicatorOffsetY", 0, "restedStateIndicatorLayer", 7)
    resting.symbol = StatusString(conf, general, "restedStateIndicatorSymbol", "DEFAULT", "restingStateIndicatorSymbol")
    local incomingRes = CompileStatusEntry(status, "incomingRes", conf, general, key, "showIncomingResIndicator", true, "incomingResIndicatorSize", 18, "incomingResIndicatorAnchor", "TOPRIGHT", "incomingResIndicatorOffsetX", 0, "incomingResIndicatorOffsetY", 0, "incomingResIndicatorLayer", 7)
    incomingRes.symbol = StatusString(conf, general, "incomingResIndicatorSymbol", "DEFAULT")

    status.enabled = false
    if status.raidMarker.enabled then
        status.enabled = true
    end
    if status.leader.enabled then
        status.enabled = true
    end
    if status.level.enabled then
        status.enabled = true
    end
    if status.raidGroup.enabled then
        status.enabled = true
    end
    if status.elite.enabled then
        status.enabled = true
    end
    if status.statusText.enabled then
        status.enabled = true
    end
    if status.combat.enabled then
        status.enabled = true
    end
    if status.resting.enabled then
        status.enabled = true
    end
    if status.incomingRes.enabled then
        status.enabled = true
    end

    out.auras = out.auras or {}
    local A3 = MSUF.MSUF_Auras3 or _G.MSUF_Auras3
    out.auras.enabled = A3 and A3.UnitFrameAuraEnabled and A3.UnitFrameAuraEnabled(unit) == true or false

    out.castbar = out.castbar or {}
    out.castbar.enabled = CastbarEnabled(unit, key, general)

    out.classPower = out.classPower or {}
    out.classPower.enabled = key == "player" and bars.showClassPower ~= false or false

    return out
end

Config.specs = Config.specs or {}

local function ConfigInCombat()
    return InCombatLockdown and InCombatLockdown()
end

function Config.BossLayoutDelta(conf, index)
    return BossLayoutDelta(conf, index, DEFAULTS.boss)
end

function Config.BossLayoutOffset(conf, index)
    return BossOffset(conf, index, DEFAULTS.boss)
end

function Config.Refresh()
    if ConfigInCombat() then
        Config.dirty = true
        return Config.specs
    end
    local db = EnsureDB()
    for i = 1, #UF.unitOrder do
        local unit = UF.unitOrder[i]
        Config.specs[unit] = ResolveUnit(db, unit, Config.specs[unit])
    end
    Config.serial = (Config.serial or 0) + 1
    Config.dirty = nil
    return Config.specs
end

_G.MSUF_GetBossLayoutDelta = function(index, conf)
    local db = EnsureDB()
    conf = conf or (db and db.boss) or {}
    return BossLayoutDelta(conf, index, DEFAULTS.boss)
end

function Config.RefreshUnit(unit)
    if not (unit and UF.IsManagedUnit and UF.IsManagedUnit(unit)) then
        return nil
    end
    if ConfigInCombat() then
        Config.dirty = true
        return Config.specs[unit]
    end
    local db = EnsureDB()
    Config.specs[unit] = ResolveUnit(db, unit, Config.specs[unit])
    Config.serial = (Config.serial or 0) + 1
    return Config.specs[unit]
end

function Config.GetSpec(unit)
    if Config.dirty == true and not ConfigInCombat() then
        Config.Refresh()
    end
    if not Config.specs[unit] then
        Config.Refresh()
    end
    return Config.specs[unit]
end

function Config.GetDB()
    return EnsureDB()
end

function Config.GetUnitDB(unit)
    local db = EnsureDB()
    return db[UF.ConfigKeyForUnit(unit)]
end

Config.settingsCache = Config.settingsCache or {}

local function BuildSettingsCache(db)
    local cache = Config.settingsCache
    local general = type(db.general) == "table" and db.general or {}
    local bars = type(db.bars) == "table" and db.bars or {}
    local dr, dg, dbb
    local dark = {}
    ResolveDarkColor(general, dark)
    dr, dg, dbb = dark.r, dark.g, dark.b
    local healthBg = ResolveHealthBackground(general, bars, nil, cache._healthBg or {})
    cache._healthBg = healthBg
    local powerBg = ResolvePowerBackground(general, bars, nil, cache._powerBg or {})
    cache._powerBg = powerBg

    cache.dbRef = db
    cache.generalRef = general
    cache.barsRef = bars
    cache.settingsSerial = Config.serial or 0
    cache.barMode = ResolveBarMode(general)
    cache.darkMode = general.darkMode == true
    cache.darkBgBrightness = Clamp01(general.darkBgBrightness, 0.25)
    cache.darkBarR, cache.darkBarG, cache.darkBarB = dr, dg, dbb
    cache.unifiedBarR = Number(general.unifiedBarR, 0.1)
    cache.unifiedBarG = Number(general.unifiedBarG, 0.6)
    cache.unifiedBarB = Number(general.unifiedBarB, 0.9)
    cache.healthGradientEnabled = general.enableHealthGradient ~= false
    cache.barBackgroundAlpha = ResolveBgAlpha(general, bars)
    cache.barBgTintR, cache.barBgTintG, cache.barBgTintB, cache.barBgTintA = healthBg.r, healthBg.g, healthBg.b, healthBg.a
    cache.powerBgTintR, cache.powerBgTintG, cache.powerBgTintB, cache.powerBgTintA = powerBg.r, powerBg.g, powerBg.b, powerBg.a
    cache.barBgClassColor = general.barBgClassColor == true
    cache.barBgMatchHPColor = general.barBgMatchHPColor == true
    cache.powerBarBgMatchHPColor = general.powerBarBgMatchBarColor == true or bars.powerBarBgMatchBarColor == true
    cache.petFrameColorEnabled = general.petFrameColorEnabled == true
    cache.petFrameColorR = Number(general.petFrameColorR, 0)
    cache.petFrameColorG = Number(general.petFrameColorG, 0.8)
    cache.petFrameColorB = Number(general.petFrameColorB, 0)
    cache.npcColorMode = general.npcColorMode == "type" and "type" or "reaction"
    cache.npcTypeColorBar = general.npcTypeColorBar ~= false
    cache.npcTypeColorText = general.npcTypeColorText ~= false
    cache.npcTypeTarget = general.npcTypeTarget ~= false
    cache.npcTypeFocus = general.npcTypeFocus ~= false
    cache.npcTypeBoss = general.npcTypeBoss ~= false
    cache.npcTypeToT = general.npcTypeToT ~= false
    cache.classColors = cache.classColors or {}
    local classColors = type(db.classColors) == "table" and db.classColors or nil
    local palette = MSUF.MSUF_FONT_COLORS or _G.MSUF_FONT_COLORS
    for i = 1, #CLASS_TOKENS do
        local token = CLASS_TOKENS[i]
        local dst = cache.classColors[token] or {}
        cache.classColors[token] = dst
        local src = classColors and classColors[token]
        if type(src) == "table" and tonumber(src.r or src[1]) and tonumber(src.g or src[2]) and tonumber(src.b or src[3]) then
            dst.r, dst.g, dst.b = Number(src.r or src[1], 1), Number(src.g or src[2], 1), Number(src.b or src[3], 1)
        elseif type(src) == "string" and palette and palette[src] then
            local c = palette[src]
            dst.r, dst.g, dst.b = Number(c.r or c[1], 1), Number(c.g or c[2], 1), Number(c.b or c[3], 1)
        else
            local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
            dst.r, dst.g, dst.b = c and c.r or 0.12, c and c.g or 0.62, c and c.b or 0.95
        end
    end
    cache.npcColors = cache.npcColors or {}
    local npcColors = type(db.npcColors) == "table" and db.npcColors or nil
    for kind, fallback in pairs(NPC_COLOR_DEFAULTS) do
        local dst = cache.npcColors[kind] or {}
        cache.npcColors[kind] = dst
        local src = npcColors and npcColors[kind]
        if type(src) == "table" then
            dst.r = Number(src.r or src[1], fallback[1])
            dst.g = Number(src.g or src[2], fallback[2])
            dst.b = Number(src.b or src[3], fallback[3])
        else
            dst.r, dst.g, dst.b = fallback[1], fallback[2], fallback[3]
        end
    end
    return cache
end

function Config.GetSettingsCache()
    local db = EnsureDB()
    local cache = Config.settingsCache
    if Config.dirty == true and ConfigInCombat() and cache.dbRef ~= nil then
        return cache
    end
    if cache.dbRef == db and cache.settingsSerial == (Config.serial or 0) then
        return cache
    end
    return BuildSettingsCache(db)
end

_G.MSUF_UFCore_GetSettingsCache = Config.GetSettingsCache

function Config.RefreshSettingsCache()
    if ConfigInCombat() then
        Config.dirty = true
        return Config.settingsCache
    end
    Config.Refresh()
    return Config.GetSettingsCache()
end

_G.MSUF_UFCore_RefreshSettingsCache = Config.RefreshSettingsCache

_G.MSUF_UFCore_GetClassBarColorFast = function(classToken)
    local cache = Config.GetSettingsCache()
    local c = cache and cache.classColors and cache.classColors[classToken]
    if c then
        return c.r, c.g, c.b
    end
    c = classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
    if c then
        return c.r, c.g, c.b
    end
    return 0.12, 0.62, 0.95
end

_G.MSUF_UFCore_GetNPCReactionColorFast = function(kind)
    local cache = Config.GetSettingsCache()
    local c = cache and cache.npcColors and cache.npcColors[kind]
    if c then
        return c.r, c.g, c.b
    end
    if kind == "friendly" then return 0, 1, 0 end
    if kind == "neutral" then return 1, 1, 0 end
    if kind == "dead" then return 0.4, 0.4, 0.4 end
    if kind == "npcBoss" then return 0.74, 0.11, 0 end
    if kind == "npcMiniboss" then return 0.56, 0, 0.74 end
    if kind == "npcCaster" then return 0, 0.45, 0.74 end
    if kind == "npcMelee" then return 0.99, 0.99, 0.99 end
    if kind == "npcRegular" then return 0.70, 0.56, 0.33 end
    return 0.85, 0.10, 0.10
end
