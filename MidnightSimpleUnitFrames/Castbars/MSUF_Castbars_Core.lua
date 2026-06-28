--- Castbars/MSUF_Castbars_Core.lua
--- Castbar settings, media resolution, font helpers, visual refresh glue, and
--- global compatibility exports.
---
--- This is a compatibility hub rather than a clean ownership layer. Keep new
--- feature logic in the newer readable modules when possible, and use this file
--- mainly to preserve old globals and bridge profile/media settings.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local type = type
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local math_floor = math.floor
local math_max = math.max

local lsm = (MSUF and MSUF.LSM) or _G.MSUF_LSM or (_G.LibStub and _G.LibStub("LibSharedMedia-3.0", true))
local fontList = _G.MSUF_FONT_LIST

local function IsOptionEnabled(db, key, defaultValue)
    local utilEnabled = MSUF and MSUF.Util and MSUF.Util.Enabled
    if type(utilEnabled) == "function" then
        return utilEnabled(nil, db, key, defaultValue)
    end

    if type(db) ~= "table" then return defaultValue ~= false end
    local value = db[key]
    if value == nil then return defaultValue ~= false end
    return value ~= false
end

local function GetLSM()
    local resolved = (MSUF and MSUF.LSM) or _G.MSUF_LSM or lsm
    if resolved then lsm = resolved end
    return resolved
end

local function IsKnownAsset(path)
    if type(path) ~= "string" or path == "" then return false end

    local validator = _G.MSUF_IsKnownFileAsset
    if type(validator) == "function" and validator(path) == false then
        return false
    end
    return true
end

local function ResolveFontPath(path, size, flags)
    local resolver = _G.MSUF_ResolveFontPath
    if type(resolver) == "function" then
        return resolver(path, size, flags)
    end
    if type(_G.MSUF_NormalizeFontPath) == "function" then
        return _G.MSUF_NormalizeFontPath(path)
    end
    return path
end

local function IsInCombat()
    return _G.MSUF_InCombat == true
        or ((_G.InCombatLockdown and _G.InCombatLockdown()) and true or false)
        or ((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) and true or false)
end

ExportPublic("MSUF_BossTestMode", _G.MSUF_BossTestMode or false)

ExportPublic("MSUF_CastbarUnitInfo", _G.MSUF_CastbarUnitInfo or {
    player = {
        label = "Player Castbar",
        prefix = "castbarPlayer",
        defaultX = 0,
        defaultY = 5,
        showTimeKey = "showPlayerCastTime",
        isBoss = false,
    },
    target = {
        label = "Target Castbar",
        prefix = "castbarTarget",
        defaultX = 65,
        defaultY = -15,
        showTimeKey = "showTargetCastTime",
        isBoss = false,
    },
    focus = {
        label = "Focus Castbar",
        prefix = "castbarFocus",
        defaultX = 65,
        defaultY = -15,
        showTimeKey = "showFocusCastTime",
        isBoss = false,
    },
    boss = {
        label = "Boss Castbar",
        prefix = nil,
        defaultX = 0,
        defaultY = 0,
        showTimeKey = "showBossCastTime",
        isBoss = true,
    },
})

local function GetCastbarUnitInfo(unit)
    local info = _G.MSUF_CastbarUnitInfo
    return info and info[unit] or nil
end
ExportPublic("MSUF_GetCastbarUnitInfo", GetCastbarUnitInfo)

local function IsBossCastbarUnit(unit)
    local info = GetCastbarUnitInfo(unit)
    return (info and info.isBoss) and true or false
end
ExportPublic("MSUF_IsBossCastbarUnit", IsBossCastbarUnit)

local function GetCastbarPrefix(unit)
    local info = GetCastbarUnitInfo(unit)
    return info and info.prefix or nil
end
ExportPublic("MSUF_GetCastbarPrefix", GetCastbarPrefix)

local function GetCastbarDefaultOffsets(unit)
    local info = GetCastbarUnitInfo(unit)
    if not info then return 0, 0 end
    return info.defaultX or 0, info.defaultY or 0
end
ExportPublic("MSUF_GetCastbarDefaultOffsets", GetCastbarDefaultOffsets)

local function GetCastbarUnitFromFrame(frame)
    if not frame then return nil end
    if _G.MSUF_BossCastbarPreview and frame == _G.MSUF_BossCastbarPreview then return "boss" end
    if ( _G.MSUF_PlayerCastbar and frame == _G.MSUF_PlayerCastbar )
        or ( _G.MSUF_PlayerCastbarPreview and frame == _G.MSUF_PlayerCastbarPreview ) then
        return "player"
    end
    if ( _G.MSUF_TargetCastbar and frame == _G.MSUF_TargetCastbar )
        or ( _G.MSUF_TargetCastbarPreview and frame == _G.MSUF_TargetCastbarPreview ) then
        return "target"
    end
    if ( _G.MSUF_FocusCastbar and frame == _G.MSUF_FocusCastbar )
        or ( _G.MSUF_FocusCastbarPreview and frame == _G.MSUF_FocusCastbarPreview ) then
        return "focus"
    end
    return nil
end
ExportPublic("MSUF_GetCastbarUnitFromFrame", GetCastbarUnitFromFrame)

local function ApplyCastbarUnitAndSync(unit)
    if not unit then return end
    if not _G.MSUF_DB then _G.MSUF_EnsureDB() end

    if IsBossCastbarUnit(unit) then
        if _G.MSUF_ApplyBossCastbarPositionSetting then _G.MSUF_ApplyBossCastbarPositionSetting() end
        if _G.MSUF_ApplyBossCastbarTimeSetting then _G.MSUF_ApplyBossCastbarTimeSetting() end
        if not IsInCombat() and _G.MSUF_UpdateBossCastbarPreview then _G.MSUF_UpdateBossCastbarPreview() end
        if type(_G.MSUF_PositionCastbarPreviewUnit) == "function" then _G.MSUF_PositionCastbarPreviewUnit("boss") end
        if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then _G.MSUF_SyncCastbarPositionPopup("boss") end
        return
    end

    if unit == "player" and type(_G.MSUF_ReanchorPlayerCastBar) == "function" then
        _G.MSUF_ReanchorPlayerCastBar()
    elseif unit == "target" and type(_G.MSUF_ReanchorTargetCastBar) == "function" then
        _G.MSUF_ReanchorTargetCastBar()
    elseif unit == "focus" and type(_G.MSUF_ReanchorFocusCastBar) == "function" then
        _G.MSUF_ReanchorFocusCastBar()
    end

    if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end
    if type(_G.MSUF_PositionCastbarPreviewUnit) == "function" then _G.MSUF_PositionCastbarPreviewUnit(unit) end
    if type(_G.MSUF_UpdateCastbarEditInfo) == "function" then _G.MSUF_UpdateCastbarEditInfo(unit) end
    if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then _G.MSUF_SyncCastbarPositionPopup(unit) end
end
ExportPublic("MSUF_ApplyCastbarUnitAndSync", ApplyCastbarUnitAndSync)

local GetGlobalFontFlags

local function EnsureDB()
    local db = _G.MSUF_DB
    if not db and type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
        db = _G.MSUF_DB
    end
    if not db then
        db = {}
        ExportPublic("MSUF_DB", db)
    end
    db.general = db.general or {}
    return db
end

local function GetFontPath()
    local db = EnsureDB()
    local general = db.general
    local fontKey = general.fontKey

    local resolver = _G.MSUF_GetFontPathForKey or (MSUF and MSUF.MSUF_GetFontPathForKey)
    if type(resolver) == "function" and fontKey and fontKey ~= "" then
        local path = resolver(fontKey)
        if path then return ResolveFontPath(path, general.fontSize or 14, GetGlobalFontFlags()) end
    end

    local internalPath
    if type(_G.MSUF_GetInternalFontPathByKey) == "function" then
        internalPath = _G.MSUF_GetInternalFontPathByKey(fontKey)
    end
    if internalPath then return ResolveFontPath(internalPath, general.fontSize or 14, GetGlobalFontFlags()) end

    local media = lsm or (MSUF and MSUF.LSM) or _G.MSUF_LSM
    if media and fontKey and fontKey ~= "" then
        local normalizer = _G.MSUF_NormalizeFontKey or function(value) return value end
        local normalized = normalizer(fontKey)
        local fetched
        if type(media.Fetch) == "function" then
            fetched = media:Fetch("font", normalized, true)
            if not fetched and normalized ~= fontKey then fetched = media:Fetch("font", fontKey, true) end
        end
        if fetched then return ResolveFontPath(fetched, general.fontSize or 14, GetGlobalFontFlags()) end
    end

    local fallback = (fontList and fontList[1] and fontList[1].path) or "Fonts\\FRIZQT__.TTF"
    return ResolveFontPath(fallback, general.fontSize or 14, GetGlobalFontFlags())
end

GetGlobalFontFlags = function()
    local db = EnsureDB()
    local general = db.general

    if general.noOutline then
        if general.fontMonochrome then return "MONOCHROME" end
        return ""
    elseif general.boldText then
        if general.fontMonochrome then return "THICKOUTLINE,MONOCHROME" end
        return "THICKOUTLINE"
    end

    if general.fontMonochrome then return "OUTLINE,MONOCHROME" end
    return "OUTLINE"
end

local function GetGlobalFontSettings()
    local db = EnsureDB()
    local general = db.general or {}
    local fontPath = GetFontPath()
    local fontFlags = GetGlobalFontFlags()
    local red, green, blue = 1, 1, 1
    if MSUF and type(MSUF.MSUF_GetConfiguredFontColor) == "function" then
        red, green, blue = MSUF.MSUF_GetConfiguredFontColor()
    end
    local fontSize = general.fontSize or 14
    local textBackdrop = general.textBackdrop ~= false
    return fontPath, fontFlags, red, green, blue, fontSize, textBackdrop
end
MSUF.MSUF_GetGlobalFontSettings = GetGlobalFontSettings
ExportPublic("MSUF_GetGlobalFontSettings", GetGlobalFontSettings)

local function ResolveTextureCandidate(key)
    if type(key) ~= "string" or key == "" then return nil, true end

    local builtin = _G.MSUF_BUILTIN_BAR_TEXTURES
    if type(builtin) == "table" then
        local path = builtin[key]
        if type(path) == "string" and path ~= "" then
            if IsKnownAsset(path) then return path, true end
            return nil, false
        end
    end

    if key:find("\\") or key:find("/") then
        if IsKnownAsset(key) then return key, true end
        return nil, false
    end

    local media = GetLSM()
    if media and media.Fetch then
        local path = media:Fetch("statusbar", key, true)
        if type(path) == "string" and path ~= "" then
            if IsKnownAsset(path) then return path, true end
            return nil, false
        end
    end

    return nil, false
end

local function GetCastbarTexture()
    local db = EnsureDB()
    local general = db.general
    local castbarKey = general and general.castbarTexture or nil
    local barKey = general and general.barTexture or nil

    local cache = _G.MSUF_CastbarTextureCache
    if not cache then
        cache = {}
        ExportPublic("MSUF_CastbarTextureCache", cache)
    end

    local cacheKey = (castbarKey or "") .. "|" .. (barKey or "")
    local cached = cache[cacheKey]
    if cached ~= nil then return cached end

    local texture, cacheable = ResolveTextureCandidate(castbarKey)
    if not texture then
        local fallbackTexture, fallbackCacheable = ResolveTextureCandidate(barKey)
        texture = fallbackTexture
        cacheable = cacheable and fallbackCacheable
    end
    texture = texture or "Interface\\TARGETINGFRAME\\UI-StatusBar"
    if cacheable then cache[cacheKey] = texture end
    return texture
end
ExportPublic("MSUF_GetCastbarTexture", GetCastbarTexture)

local function GetCastbarBackgroundTexture()
    local db = EnsureDB()
    local general = db.general
    local key = general and general.castbarBackgroundTexture or nil
    if key == nil or key == "" then key = general and general.castbarTexture end
    if key == nil or key == "" then key = general and general.barTexture end

    local cache = _G.MSUF_CastbarBackgroundTextureCache
    if not cache then
        cache = {}
        ExportPublic("MSUF_CastbarBackgroundTextureCache", cache)
    end

    local cacheKey = key or ""
    local cached = cache[cacheKey]
    if cached then return cached end

    local texture
    if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
        texture = _G.MSUF_ResolveStatusbarTextureKey(key)
    end
    if not texture or texture == "" then texture = "Interface\\TARGETINGFRAME\\UI-StatusBar" end
    cache[cacheKey] = texture
    return texture
end
ExportPublic("MSUF_GetCastbarBackgroundTexture", GetCastbarBackgroundTexture)

local function IsCastTimeEnabledForFrame(frame)
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    if not (frame and frame.unit and general) then return true end

    local unit = frame.unit
    local showTimeKey = (unit == "player" and "showPlayerCastTime")
        or (unit == "target" and "showTargetCastTime")
        or (unit == "focus" and "showFocusCastTime")
    return (not showTimeKey) and true or IsOptionEnabled(general, showTimeKey, true)
end

local function GetCastbarReverseFill(isChanneled)
    EnsureDB()
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local fillDirection = general and general.castbarFillDirection or "RTL"
    local unifiedDirection = general and general.castbarUnifiedDirection or false

    if fillDirection == "LEFT" then
        fillDirection = "RTL"
    elseif fillDirection == "RIGHT" then
        fillDirection = "LTR"
    end
    if fillDirection ~= "RTL" and fillDirection ~= "LTR" then fillDirection = "RTL" end

    local cache = _G.MSUF_CastbarReverseFillCache
    if not cache then
        cache = {}
        ExportPublic("MSUF_CastbarReverseFillCache", cache)
    end

    local cacheKey = (fillDirection == "RTL" and 4 or 0)
        + (unifiedDirection and 2 or 0)
        + (isChanneled and 1 or 0)
    local cached = cache[cacheKey]
    if cached ~= nil then return cached end

    local normalReverse = fillDirection == "RTL"
    local reverseFill
    if unifiedDirection then
        reverseFill = normalReverse
    elseif isChanneled then
        reverseFill = not normalReverse
    else
        reverseFill = normalReverse
    end
    cache[cacheKey] = reverseFill and true or false
    return cache[cacheKey]
end
ExportPublic("MSUF_GetCastbarReverseFill", GetCastbarReverseFill)

if not _G.MSUF_CastbarStyleRevision then ExportPublic("MSUF_CastbarStyleRevision", 1) end

local function BumpCastbarStyleRevision()
    local revision = _G.MSUF_CastbarStyleRevision or 1
    ExportPublic("MSUF_CastbarStyleRevision", revision + 1)
    return _G.MSUF_CastbarStyleRevision
end
ExportPublic("MSUF_BumpCastbarStyleRevision", BumpCastbarStyleRevision)

local function GetGlobalCastbarStyleCache()
    local revision = _G.MSUF_CastbarStyleRevision or 1
    local cache = _G.MSUF_GlobalCastbarStyleCache
    if cache and cache.rev == revision then return cache end

    cache = cache or {}
    cache.rev = revision
    local db = EnsureDB()
    local general = (db and db.general) or {}
    cache.unifiedDirection = general.castbarUnifiedDirection == true

    local texture = GetCastbarTexture()
    if not texture or texture == "" then texture = "Interface\\TARGETINGFRAME\\UI-StatusBar" end
    cache.texture = texture

    local bgTexture = GetCastbarBackgroundTexture()
    if not bgTexture or bgTexture == "" then bgTexture = texture end
    cache.bgTexture = bgTexture
    cache.reverseFillNormal = GetCastbarReverseFill(false) and true or false
    cache.reverseFillChanneled = GetCastbarReverseFill(true) and true or false
    ExportPublic("MSUF_GlobalCastbarStyleCache", cache)
    return cache
end
ExportPublic("MSUF_GetGlobalCastbarStyleCache", GetGlobalCastbarStyleCache)

local function RefreshCastbarStyleCache(frame)
    if not frame then return end

    local revision = _G.MSUF_CastbarStyleRevision or 1
    if frame.MSUF_castbarStyleRev == revision then return end

    local cache = GetGlobalCastbarStyleCache()
    frame.MSUF_castbarStyleRev = revision
    if cache then
        frame.MSUF_cachedUnifiedDirection = cache.unifiedDirection == true
        frame.MSUF_cachedCastbarTexture = cache.texture
        frame.MSUF_cachedCastbarBackgroundTexture = cache.bgTexture or cache.texture
        frame.MSUF_cachedReverseFillNormal = cache.reverseFillNormal == true
        frame.MSUF_cachedReverseFillChanneled = cache.reverseFillChanneled == true
    end
end
ExportPublic("MSUF_RefreshCastbarStyleCache", RefreshCastbarStyleCache)

local function GetCastbarReverseFillForFrame(frame, isChanneled)
    RefreshCastbarStyleCache(frame)
    if frame then
        return (isChanneled and frame.MSUF_cachedReverseFillChanneled or frame.MSUF_cachedReverseFillNormal) == true
    end
    return GetCastbarReverseFill(isChanneled) and true or false
end
ExportPublic("MSUF_GetCastbarReverseFillForFrame", GetCastbarReverseFillForFrame)

local function ForEachCastbarFrame(callback)
    callback(_G.MSUF_PlayerCastbar)
    callback(_G.MSUF_TargetCastbar)
    callback(_G.MSUF_FocusCastbar)
    callback(_G.MSUF_PlayerCastbarPreview)
    callback(_G.MSUF_TargetCastbarPreview)
    callback(_G.MSUF_FocusCastbarPreview)
end

local function UpdateTextureForFrame(frame, texture, bgTexture, revision)
    if frame and frame.statusBar then
        frame.statusBar:SetStatusBarTexture(texture)
        local statusTexture = frame.statusBar:GetStatusBarTexture()
        if statusTexture then statusTexture:SetHorizTile(true) end
        frame.MSUF_castbarStyleRev = revision
        frame.MSUF_cachedCastbarTexture = texture
        frame.MSUF_cachedReverseFillNormal = GetCastbarReverseFill(false) and true or false
        frame.MSUF_cachedReverseFillChanneled = GetCastbarReverseFill(true) and true or false
        EnsureDB()
        local general = _G.MSUF_DB and _G.MSUF_DB.general
        frame.MSUF_cachedUnifiedDirection = (general and general.castbarUnifiedDirection) == true
    end
    if frame and frame.backgroundBar then
        frame.backgroundBar:SetTexture(bgTexture)
        frame.MSUF_cachedCastbarBackgroundTexture = bgTexture
    end
end

local function UpdateCastbarTextures()
    BumpCastbarStyleRevision()
    local revision = _G.MSUF_CastbarStyleRevision or 1
    local texture = GetCastbarTexture()
    if not texture then return end

    local bgTexture = GetCastbarBackgroundTexture()
    if not bgTexture or bgTexture == "" then bgTexture = texture end

    ForEachCastbarFrame(function(frame)
        UpdateTextureForFrame(frame, texture, bgTexture, revision)
    end)

    local bossCastbars = _G.MSUF_BossCastbars
    if type(bossCastbars) == "table" then
        for index = 1, #bossCastbars do
            UpdateTextureForFrame(bossCastbars[index], texture, bgTexture, revision)
        end
    end
end
ExportPublic("MSUF_UpdateCastbarTextures", UpdateCastbarTextures)

local function UpdateCastbarFillDirection()
    BumpCastbarStyleRevision()

    local function ApplyFillDirectionForFrame(frame)
        if not (frame and frame.statusBar and frame.statusBar.SetReverseFill) then return end

        local isChanneled = false
        if frame.isEmpower then
            isChanneled = true
        elseif frame.MSUF_isChanneled then
            isChanneled = true
        elseif frame.unit and (frame.unit == "player" or frame.unit == "target" or frame.unit == "focus") then
            if _G.UnitChannelInfo and _G.UnitChannelInfo(frame.unit) then isChanneled = true end
        end

        RefreshCastbarStyleCache(frame)
        local reverseFill = GetCastbarReverseFillForFrame(frame, isChanneled)
        frame.statusBar:SetReverseFill(reverseFill and true or false)
    end

    ForEachCastbarFrame(ApplyFillDirectionForFrame)
end
ExportPublic("MSUF_UpdateCastbarFillDirection", UpdateCastbarFillDirection)

local resolvedStatusbarTextureCache = {}

local function ClearResolvedStatusbarTextureCache()
    resolvedStatusbarTextureCache = {}
    local castbarTextureCache = _G.MSUF_CastbarTextureCache
    if type(castbarTextureCache) == "table" then
        for key in pairs(castbarTextureCache) do castbarTextureCache[key] = nil end
    end

    local detachedTextures = MSUF and MSUF.Bars and MSUF.Bars._DetachedPowerBarTextures
    if detachedTextures then
        detachedTextures.fgK = false
        detachedTextures.fgC = nil
        detachedTextures.bgK = false
        detachedTextures.bgC = nil
    end
    GetLSM()
end
ExportPublic("MSUF_ClearResolvedStatusbarTextureCache", ClearResolvedStatusbarTextureCache)

local function ResolveStatusbarTextureKey(key)
    if type(key) ~= "string" or key == "" then return "Interface\\TargetingFrame\\UI-StatusBar" end

    local cached = resolvedStatusbarTextureCache[key]
    if cached then return cached end

    local resolved
    local cacheable = false
    local builtin = _G.MSUF_BUILTIN_BAR_TEXTURES
    if type(builtin) == "table" then
        local path = builtin[key]
        if type(path) == "string" and path ~= "" and IsKnownAsset(path) then
            resolved = path
            cacheable = true
        end
    end

    if not resolved then
        if key:find("\\") or key:find("/") then
            if IsKnownAsset(key) then
                resolved = key
                cacheable = true
            end
        else
            local media = GetLSM()
            if media and type(media.Fetch) == "function" then
                local fetched = media:Fetch("statusbar", key, true)
                if type(fetched) == "string" and fetched ~= "" and IsKnownAsset(fetched) then
                    resolved = fetched
                    cacheable = true
                end
            end
        end
    end

    if resolved then
        if cacheable then resolvedStatusbarTextureCache[key] = resolved end
        return resolved
    end

    local fallback = "Interface\\TargetingFrame\\UI-StatusBar"
    if cacheable then resolvedStatusbarTextureCache[key] = fallback end
    return fallback
end
ExportPublic("MSUF_ResolveStatusbarTextureKey", ResolveStatusbarTextureKey)

ExportPublic("MSUF_BUILTIN_BAR_TEXTURES", _G.MSUF_BUILTIN_BAR_TEXTURES or {
    Blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
    Flat = "Interface\\Buttons\\WHITE8x8",
    RaidHP = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    RaidPower = "Interface\\RaidFrame\\Raid-Bar-Resource-Fill",
    Skills = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    Outline = "Interface\\Tooltips\\UI-Tooltip-Background",
    TooltipBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
    DialogBG = "Interface\\DialogFrame\\UI-DialogBox-Background",
    Parchment = "Interface\\AchievementFrame\\UI-Achievement-StatsBackground",
})

local function GetBarTexture()
    local db = EnsureDB()
    local general = (db and db.general) or nil
    return ResolveStatusbarTextureKey(general and general.barTexture)
end
ExportPublic("MSUF_GetBarTexture", GetBarTexture)

local function GetBarBackgroundTexture()
    local db = EnsureDB()
    local general = (db and db.general) or nil
    local key = general and general.barBackgroundTexture
    if key == nil or key == "" then key = general and general.barTexture end
    return ResolveStatusbarTextureKey(key)
end
ExportPublic("MSUF_GetBarBackgroundTexture", GetBarBackgroundTexture)

local function ApplyFont(fontString, fontPath, fontSize, fontFlags, red, green, blue, alpha)
    fontSize = tonumber(fontSize) or 12
    if fontSize <= 0 then fontSize = 12 end
    if fontSize < 6 then fontSize = 6 elseif fontSize > 128 then fontSize = 128 end
    if fontPath and fontString.SetFont then
        pcall(fontString.SetFont, fontString, fontPath, fontSize, fontFlags)
    end
    fontString:SetTextColor(red, green, blue, alpha)
end

local function ApplyShadow(fontString, enabled, alpha, offsetX, offsetY)
    if enabled then
        fontString:SetShadowColor(0, 0, 0, alpha)
        fontString:SetShadowOffset(offsetX, offsetY)
    else
        fontString:SetShadowOffset(0, 0)
    end
end

local function ApplySparkLayout(frame, statusBar, general, height)
    local enabled = general and general.castbarShowSpark == true
    local spark = frame.spark
    if enabled and not spark then
        spark = statusBar:CreateTexture(nil, "OVERLAY", nil, 6)
        spark:SetTexture(4417031)
        spark:SetTexCoord(0.222168, 0.232422, 0.294434, 0.317383)
        spark:SetDesaturated(true)
        spark:SetVertexColor(1, 1, 1, 1)
        spark:SetBlendMode("ADD")
        frame.spark = spark
    end
    if not spark then return end

    spark:SetShown(enabled)
    if enabled then
        local allowOverflow = general and general.castbarSparkOverflow ~= false
        local sparkHeight = allowOverflow and math_max(4, height * 2.1) or height
        spark:SetSize(16, sparkHeight)
        local texture = statusBar:GetStatusBarTexture()
        if texture then
            spark:ClearAllPoints()
            spark:SetPoint("CENTER", texture, "RIGHT", 0, 0)
        end
    end
end

local function ApplyCastbarVisualFrame(frame, context)
    if not frame or not frame.statusBar then return end

    local statusBar = frame.statusBar
    local icon = frame.icon
        or frame.Icon
        or (frame.IconFrame and (frame.IconFrame.Icon or frame.IconFrame.icon))
        or frame.iconTexture
        or frame.IconTexture
    local width = frame:GetWidth() or statusBar:GetWidth() or 250
    local height = frame:GetHeight() or statusBar:GetHeight() or 18
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local unit, prefix
    local widthSourceLocked = false

    if general then
        local globalWidth = tonumber(general.castbarGlobalWidth)
        local globalHeight = tonumber(general.castbarGlobalHeight)
        unit = GetCastbarUnitFromFrame(frame)
        local normalizer = _G.MSUF_NormalizeCastbarWidthSource or _G.MSUF_NormalizePlayerCastbarWidthSource
        local widthSourceKey = _G.MSUF_GetCastbarWidthSourceKey and _G.MSUF_GetCastbarWidthSourceKey(unit)
        if widthSourceKey then
            local widthSource = general[widthSourceKey]
            if type(normalizer) == "function" then
                widthSourceLocked = normalizer(widthSource) ~= nil
            elseif widthSource == "unitframe" or widthSource == "essential" or widthSource == "utility" then
                widthSourceLocked = true
            end
        end

        if globalWidth and globalWidth > 0 and not widthSourceLocked then width = globalWidth; frame:SetWidth(width) end
        if globalHeight and globalHeight > 0 then height = globalHeight; frame:SetHeight(globalHeight) end
        prefix = unit and GetCastbarPrefix(unit) or nil
        if prefix then
            local unitWidth = tonumber(general[prefix .. "BarWidth"])
            local unitHeight = tonumber(general[prefix .. "BarHeight"])
            if unitWidth and unitWidth > 0 and not widthSourceLocked then width = unitWidth; frame:SetWidth(width) end
            if unitHeight and unitHeight > 0 then height = unitHeight; frame:SetHeight(unitHeight) end
        end
    end

    local showIcon = context.showIcon
    local iconOffsetX = context.iconOffsetX
    local iconOffsetY = context.iconOffsetY
    local iconSize = height
    if general then
        if prefix then
            local value = general[prefix .. "ShowIcon"]
            if value ~= nil then showIcon = value ~= false end
            value = general[prefix .. "IconOffsetX"]
            if value ~= nil then iconOffsetX = tonumber(value) or 0 end
            value = general[prefix .. "IconOffsetY"]
            if value ~= nil then iconOffsetY = tonumber(value) or 0 end
            value = general[prefix .. "IconSize"]
            if value ~= nil then
                iconSize = tonumber(value) or iconSize
            else
                local globalIconSize = tonumber(general.castbarIconSize) or 0
                if globalIconSize and globalIconSize > 0 then iconSize = globalIconSize end
            end
        else
            local globalIconSize = tonumber(general.castbarIconSize) or 0
            if globalIconSize and globalIconSize > 0 then iconSize = globalIconSize end
        end
    end
    if iconSize < 6 then iconSize = 6 elseif iconSize > 128 then iconSize = 128 end

    local isPlayerFrame = frame == _G.MSUF_PlayerCastbar or frame == _G.MSUF_PlayerCastbarPreview
    local hasDetachedIconOffset = iconOffsetX ~= 0
    local backgroundBar = frame.backgroundBar
    if isPlayerFrame and type(_G.MSUF_ApplyPlayerCastbarIconLayout) == "function" then
        _G.MSUF_ApplyPlayerCastbarIconLayout(frame, general, -1, 1)
        if backgroundBar and frame.statusBar then
            backgroundBar:ClearAllPoints()
            backgroundBar:SetAllPoints(frame.statusBar)
        end
    else
        if icon and statusBar and icon.GetParent and icon.SetParent then
            local parent = hasDetachedIconOffset and statusBar or frame
            if icon:GetParent() ~= parent then icon:SetParent(parent) end
        end
        if icon then
            icon:SetShown(showIcon)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", frame, "LEFT", iconOffsetX, iconOffsetY)
            icon:SetSize(iconSize, iconSize)
            if icon.SetDrawLayer then icon:SetDrawLayer("OVERLAY", 7) end
        end

        statusBar:ClearAllPoints()
        if showIcon and icon and not hasDetachedIconOffset then
            statusBar:SetPoint("LEFT", frame, "LEFT", iconSize + 1, 0)
            statusBar:SetWidth(width - (iconSize + 1))
        else
            statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
            statusBar:SetWidth(width)
        end
        statusBar:SetHeight(height - 2)
        if backgroundBar then
            backgroundBar:ClearAllPoints()
            backgroundBar:SetAllPoints(statusBar)
        end
    end

    ApplySparkLayout(frame, statusBar, general, height)
    if _G.MSUF_KickReady_ApplyLayout then _G.MSUF_KickReady_ApplyLayout(frame) end

    local showSpellName = context.showSpellName
    local spellFontSize = context.spellFontSize
    local textOffsetX, textOffsetY = 0, 0
    local timeFontSize = spellFontSize
    local timeOffsetX, timeOffsetY = -2, 0

    if prefix then
        local value = general[prefix .. "ShowSpellName"]
        if value ~= nil then showSpellName = value ~= false end
        textOffsetX = tonumber(general[prefix .. "TextOffsetX"]) or 0
        textOffsetY = tonumber(general[prefix .. "TextOffsetY"]) or 0
        timeOffsetX = tonumber(general[prefix .. "TimeOffsetX"]) or tonumber(general.castbarPlayerTimeOffsetX) or -2
        timeOffsetY = tonumber(general[prefix .. "TimeOffsetY"]) or tonumber(general.castbarPlayerTimeOffsetY) or 0
        local unitSpellSize = tonumber(general[prefix .. "SpellNameFontSize"]) or 0
        if unitSpellSize and unitSpellSize > 0 then spellFontSize = unitSpellSize end
        local unitTimeSize = tonumber(general[prefix .. "TimeFontSize"]) or 0
        if unitTimeSize and unitTimeSize > 0 then timeFontSize = unitTimeSize else timeFontSize = spellFontSize end
    elseif IsBossCastbarUnit(unit) then
        timeOffsetX = -2 + (tonumber(general.bossCastTimeOffsetX) or 0)
        timeOffsetY = tonumber(general.bossCastTimeOffsetY) or 0
        local bossTimeSize = tonumber(general.bossCastTimeFontSize) or 0
        if bossTimeSize and bossTimeSize > 0 then timeFontSize = bossTimeSize end
    end

    local castTimeEnabled = IsCastTimeEnabledForFrame(frame)
    if type(_G.MSUF_IsCastTimeEnabled) == "function" then castTimeEnabled = _G.MSUF_IsCastTimeEnabled(frame) end

    local castText = frame.castText or frame.Text or frame.text
    if castText then
        castText:SetShown(showSpellName)
        ApplyFont(castText, context.fontPath, spellFontSize, context.fontFlags, context.textR, context.textG, context.textB, context.textAlpha)
        if castText.SetMaxLines then castText:SetMaxLines(1) end
        if castText.SetWordWrap then castText:SetWordWrap(false) end
        if castText.SetNonSpaceWrap then castText:SetNonSpaceWrap(false) end
        if castText.SetPoint then
            castText:ClearAllPoints()
            castText:SetPoint("LEFT", statusBar, "LEFT", 2 + textOffsetX, textOffsetY)
        end

        local _, _, reservedSpace
        if type(_G.MSUF_GetCastbarSpellNameShorteningConfig) == "function" then
            _, _, reservedSpace = _G.MSUF_GetCastbarSpellNameShorteningConfig(frame)
        end
        local barWidth = (statusBar.GetWidth and statusBar:GetWidth()) or (frame.GetWidth and frame:GetWidth()) or 250
        if barWidth < 20 then barWidth = 20 end

        local timeWidth = 0
        if castTimeEnabled and frame.timeText then
            local size = tonumber(timeFontSize) or 12
            if size < 6 then size = 6 elseif size > 128 then size = 128 end
            local format = frame._msufCastTimeFormat
            timeWidth = math_floor(size * ((format == "CURRENT" or not format) and 3.2 or 6.8) + 8.5)
            local maxWidth = math_floor(barWidth * 0.45 + 0.5)
            if timeWidth > maxWidth then timeWidth = maxWidth end
        end

        local reserved = tonumber(reservedSpace) or 0
        local textWidth = math_floor(barWidth - timeWidth - reserved - (6 + (tonumber(textOffsetX) or 0)) + 0.5)
        if textWidth < 20 then textWidth = 20 end
        if castText.SetWidth and castText._msufCastbarTextWidth ~= textWidth then
            castText:SetWidth(textWidth)
            castText._msufCastbarTextWidth = textWidth
        end
        if type(_G.MSUF_RefreshCastbarSpellNameText) == "function" then _G.MSUF_RefreshCastbarSpellNameText(frame) end
        ApplyShadow(castText, context.shadowEnabled, context.shadowAlpha, context.shadowX, context.shadowY)
    end

    local timeText = frame.timeText
    if timeText and castTimeEnabled then
        ApplyFont(timeText, context.fontPath, timeFontSize or context.spellFontSize, context.fontFlags, context.textR, context.textG, context.textB, context.textAlpha)
        if timeText.SetPoint then
            timeText:ClearAllPoints()
            timeText:SetPoint("RIGHT", statusBar, "RIGHT", timeOffsetX, timeOffsetY)
        end
        ApplyShadow(timeText, context.shadowEnabled, context.shadowAlpha, context.shadowX, context.shadowY)
    end
end

local function UpdateCastbarVisuals()
    BumpCastbarStyleRevision()
    local db = EnsureDB()
    local general = db.general or {}

    local showIcon = IsOptionEnabled(general, "castbarShowIcon", true)
    local showSpellName = IsOptionEnabled(general, "castbarShowSpellName", true)
    local spellFontSize = tonumber(general.castbarSpellNameFontSize) or 0
    local iconOffsetX = tonumber(general.castbarIconOffsetX) or 0

    local fontPath = GetFontPath()
    local fontFlags = GetGlobalFontFlags()
    local textR, textG, textB = 1, 1, 1
    if type(_G.MSUF_GetCastbarTextColor) == "function" then
        textR, textG, textB = _G.MSUF_GetCastbarTextColor()
    elseif MSUF and type(MSUF.MSUF_GetConfiguredFontColor) == "function" then
        textR, textG, textB = MSUF.MSUF_GetConfiguredFontColor()
    else
        local colorKey = tostring(general.fontColor or "white"):lower()
        local color = (_G.MSUF_FONT_COLORS and (_G.MSUF_FONT_COLORS[colorKey] or _G.MSUF_FONT_COLORS.white)) or { 1, 1, 1 }
        textR, textG, textB = color[1], color[2], color[3]
    end

    local shadowEnabled = general.textBackdrop ~= false
    local textAlpha = tonumber(general.fontTextAlpha) or 1
    if textAlpha < 0.7 then textAlpha = 0.7 elseif textAlpha > 1 then textAlpha = 1 end

    local shadowAlpha, shadowX, shadowY = 1, 1, -1
    local shadowStrength = tostring(general.fontShadowStrength or "NORMAL"):upper()
    if shadowStrength == "SOFT" then
        shadowAlpha, shadowX, shadowY = 0.55, 1, -1
    elseif shadowStrength == "DEEP" then
        shadowAlpha, shadowX, shadowY = 1, 2, -2
    end

    local baseFontSize = tonumber(general.fontSize) or 14
    if baseFontSize <= 0 then baseFontSize = 14 end
    local effectiveSpellFontSize = spellFontSize > 0 and spellFontSize or baseFontSize

    local context = {
        showIcon = showIcon,
        showSpellName = showSpellName,
        iconOffsetX = iconOffsetX,
        iconOffsetY = textAlpha, -- Preserve current runtime behavior from the legacy compact block.
        fontPath = fontPath,
        fontFlags = fontFlags,
        textR = textR,
        textG = textG,
        textB = textB,
        textAlpha = textAlpha,
        shadowEnabled = shadowEnabled,
        shadowAlpha = shadowAlpha,
        shadowX = shadowX,
        shadowY = shadowY,
        spellFontSize = effectiveSpellFontSize,
    }

    ApplyCastbarVisualFrame(_G.MSUF_PlayerCastbar, context)
    ApplyCastbarVisualFrame(_G.MSUF_TargetCastbar, context)
    ApplyCastbarVisualFrame(_G.MSUF_FocusCastbar, context)

    if not IsInCombat() then
        ApplyCastbarVisualFrame(_G.MSUF_PlayerCastbarPreview, context)
        ApplyCastbarVisualFrame(_G.MSUF_TargetCastbarPreview, context)
        ApplyCastbarVisualFrame(_G.MSUF_FocusCastbarPreview, context)
        if _G.MSUF_BossCastbarPreview then ApplyCastbarVisualFrame(_G.MSUF_BossCastbarPreview, context) end
    end

    if not IsInCombat()
        and type(_G.MSUF_UpdateBossCastbarPreview) == "function"
        and not _G.MSUF_BossPreviewRefreshLock then
        ExportPublic("MSUF_BossPreviewRefreshLock", true)
        _G.MSUF_UpdateBossCastbarPreview()
        if _G.MSUF_SetupBossCastbarPreviewEditMode then _G.MSUF_SetupBossCastbarPreviewEditMode() end
        ExportPublic("MSUF_BossPreviewRefreshLock", false)
    end

    local maxBossFrames = _G.MSUF_MAX_BOSS_FRAMES or 5
    for index = 1, maxBossFrames do
        local frame = _G["MSUF_boss" .. index .. "CastBar"]
        if frame then ApplyCastbarVisualFrame(frame, context) end
    end
end
ExportPublic("MSUF_UpdateCastbarVisuals", UpdateCastbarVisuals)

MSUF.Castbars = MSUF.Castbars or {}
MSUF.Castbars._GetFontPath = GetFontPath
MSUF.Castbars._GetFontFlags = GetGlobalFontFlags
MSUF.MSUF_GetFontPath = GetFontPath
MSUF.MSUF_GetFontFlags = GetGlobalFontFlags
ExportPublic("MSUF_GetFontPath", GetFontPath)
ExportPublic("MSUF_GetFontFlags", GetGlobalFontFlags)
