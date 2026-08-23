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
local math_max = math.max
local math_floor = math.floor

local lsm = (MSUF and MSUF.LSM) or _G.MSUF_LSM or (_G.LibStub and _G.LibStub("LibSharedMedia-3.0", true))
local fontList = _G.MSUF_FONT_LIST

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

local function NormalizeCastbarUnit(unit)
    unit = tostring(unit or ""):lower()
    if unit:match("^boss") then return "boss" end
    return GetCastbarUnitInfo(unit) and unit or nil
end

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

local ApplyCastbarVisualsForUnit

local function ApplyCastbarUnitAndSync(unit)
    unit = NormalizeCastbarUnit(unit)
    if not unit then return end
    if not _G.MSUF_DB then _G.MSUF_EnsureDB() end

    if IsBossCastbarUnit(unit) then
        if _G.MSUF_ApplyBossCastbarPositionSetting then
            _G.MSUF_ApplyBossCastbarPositionSetting(nil, true, true)
        end
        if ApplyCastbarVisualsForUnit then
            ApplyCastbarVisualsForUnit("boss")
        elseif _G.MSUF_UpdateCastbarVisuals then
            _G.MSUF_UpdateCastbarVisuals("boss")
        end
        if type(_G.MSUF_UpdateCastbarEditInfo) == "function" then _G.MSUF_UpdateCastbarEditInfo("boss") end
        if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then _G.MSUF_SyncCastbarPositionPopup("boss") end
        return
    end

    if unit == "player" and type(_G.MSUF_ReanchorPlayerCastBarBase) == "function" then
        _G.MSUF_ReanchorPlayerCastBarBase()
    elseif unit == "target" and type(_G.MSUF_ReanchorTargetCastBarBase) == "function" then
        _G.MSUF_ReanchorTargetCastBarBase()
    elseif unit == "focus" and type(_G.MSUF_ReanchorFocusCastBarBase) == "function" then
        _G.MSUF_ReanchorFocusCastBarBase()
    end

    if ApplyCastbarVisualsForUnit then
        ApplyCastbarVisualsForUnit(unit)
    elseif _G.MSUF_UpdateCastbarVisuals then
        _G.MSUF_UpdateCastbarVisuals(unit)
    end
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

    if general.fontSlug then
        if general.noOutline then return "SLUG" end
        return "OUTLINE,SLUG"
    end
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
        and not tostring(fontFlags):upper():find("SLUG", 1, true)
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
    -- Channels keep the cast's anchor: unified direction switches the native
    -- timer between drain (RemainingTime) and fill (ElapsedTime) instead of
    -- flipping the anchor, so the anchor is direction-only for every cast type.
    local reverseFill = normalReverse
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
        -- Keep the fill stretched on every media swap; tiling repeats the 256px
        -- art and seams near the right edge on default 271/272px castbars.
        if statusTexture then statusTexture:SetHorizTile(false) end
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
ExportPublic("MSUF_UpdateCastbarTextures_Immediate", UpdateCastbarTextures)

local resolvedStatusbarTextureCache = {}

local function ClearResolvedStatusbarTextureCache()
    resolvedStatusbarTextureCache = {}
    local castbarTextureCache = _G.MSUF_CastbarTextureCache
    if type(castbarTextureCache) == "table" then
        for key in pairs(castbarTextureCache) do castbarTextureCache[key] = nil end
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
    ["MSUF Lucent"] = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\MSUF_Lucent_v2.tga",
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
            -- Moving edge = side opposite the fill anchor: LEFT when
            -- reverse-filled, RIGHT otherwise (fill and drain alike).
            local reversed = false
            if type(_G.MSUF_GetCastbarReverseFillForFrame) == "function" then
                reversed = _G.MSUF_GetCastbarReverseFillForFrame(frame, false) == true
            elseif statusBar.GetReverseFill then
                reversed = statusBar:GetReverseFill() and true or false
            end
            spark:ClearAllPoints()
            spark:SetPoint("CENTER", texture, reversed and "LEFT" or "RIGHT", 0, 0)
        end
    end
end

local function ApplyCastbarSparkVisual(frame, general)
    if not (frame and frame.statusBar) then return end
    general = general or EnsureDB().general or {}
    local height = (frame.GetHeight and frame:GetHeight()) or frame.statusBar:GetHeight() or 18
    ApplySparkLayout(frame, frame.statusBar, general, height)
end
ExportPublic("MSUF_ApplyCastbarSparkVisual", ApplyCastbarSparkVisual)

local function ApplyCastbarBaseGeometry(frame, general, forcedUnit)
    if not frame or not frame.statusBar then return end

    local statusBar = frame.statusBar
    local width = frame:GetWidth() or statusBar:GetWidth() or 250
    local height = frame:GetHeight() or statusBar:GetHeight() or 18
    general = general or EnsureDB().general or {}
    local unit, prefix
    local widthSourceLocked = false

    do
        local globalWidth = tonumber(general.castbarGlobalWidth)
        local globalHeight = tonumber(general.castbarGlobalHeight)
        unit = forcedUnit or GetCastbarUnitFromFrame(frame)
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

        if globalWidth and globalWidth > 0 and not widthSourceLocked then width = globalWidth end
        if globalHeight and globalHeight > 0 then height = globalHeight end
        prefix = unit and GetCastbarPrefix(unit) or nil
        if prefix then
            local unitWidth = tonumber(general[prefix .. "BarWidth"])
            local unitHeight = tonumber(general[prefix .. "BarHeight"])
            if unitWidth and unitWidth > 0 and not widthSourceLocked then width = unitWidth end
            if unitHeight and unitHeight > 0 then height = unitHeight end
        end

        -- Boss intentionally has no generic castbar prefix. Without this shared
        -- resolver, the visual pass falls through to castbarGlobalWidth/Height
        -- and overwrites the boss-specific geometry from the preceding anchor
        -- pass. Auto Width only masks the width half of that bug. Resolve both
        -- dimensions from the real boss settings in every width-source mode.
        if unit == "boss" and type(_G.MSUF_GetCastbarDesiredSize) == "function" then
            local desiredWidth, desiredHeight = _G.MSUF_GetCastbarDesiredSize(
                unit, general, frame, width, height)
            if desiredWidth and desiredWidth > 0 then width = desiredWidth end
            if desiredHeight and desiredHeight > 0 then height = desiredHeight end
        end
    end

    if frame:GetWidth() ~= width then frame:SetWidth(width) end
    if frame:GetHeight() ~= height then frame:SetHeight(height) end

    return general, height, width
end

local CASTBAR_FRAME_LEVEL_KEYS = {
    player = "castbarPlayerFrameLevelOffset",
    target = "castbarTargetFrameLevelOffset",
    focus = "castbarFocusFrameLevelOffset",
    boss = "bossCastFrameLevelOffset",
}

local function GetCastbarFrameLevelOffset(unit, general)
    unit = NormalizeCastbarUnit(unit)
    local key = unit and CASTBAR_FRAME_LEVEL_KEYS[unit]
    local layer = tonumber(key and general and general[key]) or 6
    layer = math_floor(layer + 0.5)
    if layer < 0 then return 0 end
    if layer > 30 then return 30 end
    return layer
end
ExportPublic("MSUF_GetCastbarFrameLevelOffset", GetCastbarFrameLevelOffset)

local function CastbarAnchorFrame(frame, unit)
    local frameUnit = frame and tostring(frame.unit or "") or ""
    if unit == "boss" and not frameUnit:match("^boss%d+$") then
        frameUnit = "boss" .. tostring(tonumber(frame and frame._msufBossIndex) or 1)
    end
    if frameUnit == "" then frameUnit = unit end

    local uf = MSUF and MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local anchor = uf.GetFrame(frameUnit)
        if anchor then return anchor end
    end
    if uf and uf.frames then
        return uf.frames[frameUnit]
    end
    return _G["MSUF_" .. frameUnit]
end

local function SetCastbarFrameLevel(frame, level)
    if not (frame and frame.SetFrameLevel) then return end
    local current = frame.GetFrameLevel and frame:GetFrameLevel() or nil
    if current ~= level then frame:SetFrameLevel(level) end
end

local function SyncCastbarFrameStrata(frame, anchor, unit)
    if not (frame and frame.SetFrameStrata) then return end
    local anchorStrata = anchor and anchor.GetFrameStrata and anchor:GetFrameStrata() or nil
    -- The owning Unit Frame and castbar must share one strata. Otherwise WoW's
    -- strata ordering always wins and the 0-30 frame-level control cannot move
    -- the castbar behind or in front of Unit Frame content.
    local wanted = anchorStrata or (unit == "boss" and "HIGH" or "MEDIUM")
    local currentStrata = frame.GetFrameStrata and frame:GetFrameStrata() or nil
    if wanted and wanted ~= "" and wanted ~= currentStrata then frame:SetFrameStrata(wanted) end
end

local CASTBAR_ICON_LAYER_KEYS = {
    player = "castbarPlayerIconFrameLevelOffset",
    target = "castbarTargetIconFrameLevelOffset",
    focus = "castbarFocusIconFrameLevelOffset",
    boss = "bossCastIconFrameLevelOffset",
}

--- Returns the manual icon frame level (1-30) or nil for 0/unset, which means
--- "follow the castbar": the icon keeps its established stack slot just above
--- the statusbar and moves together with the 0-30 whole-castbar layer.
local function ResolveCastbarIconFrameLevel(unit, general)
    unit = NormalizeCastbarUnit(unit)
    local key = unit and CASTBAR_ICON_LAYER_KEYS[unit]
    local value = tonumber(key and general and general[key])
    if not value then return nil end
    value = math_floor(value + 0.5)
    if value <= 0 then return nil end
    if value > 30 then value = 30 end
    local layers = MSUF.UF and MSUF.UF.Layers
    return layers and layers.ElementLevel and layers.ElementLevel(value, 0, 4) or value
end
ExportPublic("MSUF_ResolveCastbarIconFrameLevel", ResolveCastbarIconFrameLevel)

-- The castbar occupies one universal user-layer slot. Its children retain
-- their established detail ordering inside that slot.
local function ApplyCastbarFrameLayer(frame, general, forcedUnit)
    if not frame then return end
    local unit = NormalizeCastbarUnit(forcedUnit) or NormalizeCastbarUnit(frame.unit)
    if not unit then return end
    local layer = GetCastbarFrameLevelOffset(unit, general)

    local anchor = CastbarAnchorFrame(frame, unit)
    SyncCastbarFrameStrata(frame, anchor, unit)
    local layers = MSUF.UF and MSUF.UF.Layers
    local rootLevel = layers and layers.ElementLevel and layers.ElementLevel(layer, 0, 0) or layer
    local statusLevel = rootLevel + 1
    local iconLevel = ResolveCastbarIconFrameLevel(unit, general)
    SetCastbarFrameLevel(frame, rootLevel)
    SetCastbarFrameLevel(frame.statusBar, statusLevel)
    SetCastbarFrameLevel(frame._msufPCIconHost, iconLevel or (statusLevel + 3))
    SetCastbarFrameLevel(frame._msufDetailIconHost, iconLevel or (statusLevel + 6))
    SetCastbarFrameLevel(frame._msufDetailIconBorder, iconLevel and (iconLevel + 2) or (statusLevel + 8))
    SetCastbarFrameLevel(frame._msufTextOverlay, statusLevel + 10)
    SetCastbarFrameLevel(frame._msufOutlineHost, statusLevel + 20)
    SetCastbarFrameLevel(frame._msufRoundedCastbarOutlineHost, statusLevel + 20)
end
ExportPublic("MSUF_ApplyCastbarFrameLayer", ApplyCastbarFrameLayer)

local function ApplyCastbarVisualFrameCold(frame, general, forcedUnit)
    if not (frame and frame.statusBar) then return false end
    local height, width
    general, height, width = ApplyCastbarBaseGeometry(frame, general, forcedUnit)
    ApplyCastbarFrameLayer(frame, general, forcedUnit)
    local globalRevision = _G.MSUF__castbarStyleGlobalRev or 1
    local textureRevision = _G.MSUF_CastbarStyleRevision or 1
    if frame._msufCastbarColdGlobalRev == globalRevision
        and frame._msufCastbarColdTextureRev == textureRevision
        and frame._msufCastbarColdUnit == forcedUnit
        and frame._msufCastbarColdWidth == width
        and frame._msufCastbarColdHeight == height then
        return true
    end
    if type(_G.MSUF_RefreshCastbarFrame) == "function" then
        _G.MSUF_RefreshCastbarFrame(frame, forcedUnit, general)
    end
    ApplyCastbarSparkVisual(frame, general)
    frame._msufCastbarStyleRev = globalRevision
    frame._msufCastbarColdGlobalRev = globalRevision
    frame._msufCastbarColdTextureRev = textureRevision
    frame._msufCastbarColdUnit = forcedUnit
    frame._msufCastbarColdWidth = width
    frame._msufCastbarColdHeight = height
    return true
end

local function MaxBossFrames()
    local count = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or 5
    if count < 1 or count > 12 then return 5 end
    return count
end

local function BumpCastbarVisualRevisions()
    BumpCastbarStyleRevision()

    local bumpStyle = _G.MSUF_BumpCastbarStyleRev
    if type(bumpStyle) == "function" then bumpStyle() end

    local bumpTime = _G.MSUF_BumpCastTimeRev
    if type(bumpTime) == "function" then bumpTime() end
end

local function ApplyBossRuntimeVisuals(general)
    local did = false
    local bossCastbars = _G.MSUF_BossCastbars
    for index = 1, MaxBossFrames() do
        local frame = (bossCastbars and bossCastbars[index])
            or _G["MSUF_BossCastbar" .. index]
            or _G["MSUF_boss" .. index .. "CastBar"]
        did = ApplyCastbarVisualFrameCold(frame, general, "boss") or did
    end
    return did
end

local function ApplyExistingBossPreviewVisuals(general)
    local did = ApplyCastbarVisualFrameCold(
        _G.MSUF_BossCastbarPreview or _G.MSUF_BossCastbarPreview1,
        general,
        "boss"
    )
    for index = 2, MaxBossFrames() do
        did = ApplyCastbarVisualFrameCold(_G["MSUF_BossCastbarPreview" .. index], general, "boss") or did
    end
    return did
end

local function RefreshBossPreviews(general)
    if IsInCombat() then return false end

    local updatePreview = _G.MSUF_UpdateBossCastbarPreview
    if type(updatePreview) == "function" and not _G.MSUF_BossPreviewRefreshLock then
        ExportPublic("MSUF_BossPreviewRefreshLock", true)
        updatePreview()
        local setupEditMode = _G.MSUF_SetupBossCastbarPreviewEditMode
        if type(setupEditMode) == "function" then setupEditMode() end
        ExportPublic("MSUF_BossPreviewRefreshLock", false)
        return true
    end

    return ApplyExistingBossPreviewVisuals(general)
end

ApplyCastbarVisualsForUnit = function(unit, revisionsReady, general)
    unit = IsBossCastbarUnit(unit) and "boss" or tostring(unit or "")
    if not revisionsReady then BumpCastbarVisualRevisions() end
    general = general or EnsureDB().general or {}
    local did = false
    if unit == "player" then
        did = ApplyCastbarVisualFrameCold(_G.MSUF_PlayerCastbar, general, unit) or did
        if not IsInCombat() then did = ApplyCastbarVisualFrameCold(_G.MSUF_PlayerCastbarPreview, general, unit) or did end
    elseif unit == "target" then
        did = ApplyCastbarVisualFrameCold(_G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar, general, unit) or did
        if not IsInCombat() then did = ApplyCastbarVisualFrameCold(_G.MSUF_TargetCastbarPreview, general, unit) or did end
    elseif unit == "focus" then
        did = ApplyCastbarVisualFrameCold(_G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar, general, unit) or did
        if not IsInCombat() then did = ApplyCastbarVisualFrameCold(_G.MSUF_FocusCastbarPreview, general, unit) or did end
    elseif unit == "boss" then
        did = ApplyBossRuntimeVisuals(general) or did
        did = RefreshBossPreviews(general) or did
    end
    return did
end
ExportPublic("MSUF_ApplyCastbarVisualsForUnit", ApplyCastbarVisualsForUnit)

local function ApplyAllCastbarVisuals(general)
    ApplyCastbarVisualFrameCold(_G.MSUF_PlayerCastbar, general, "player")
    ApplyCastbarVisualFrameCold(_G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar, general, "target")
    ApplyCastbarVisualFrameCold(_G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar, general, "focus")

    if not IsInCombat() then
        ApplyCastbarVisualFrameCold(_G.MSUF_PlayerCastbarPreview, general, "player")
        ApplyCastbarVisualFrameCold(_G.MSUF_TargetCastbarPreview, general, "target")
        ApplyCastbarVisualFrameCold(_G.MSUF_FocusCastbarPreview, general, "focus")
    end

    ApplyBossRuntimeVisuals(general)
    RefreshBossPreviews(general)
end

local function UpdateCastbarVisuals(unit)
    unit = NormalizeCastbarUnit(unit)
    BumpCastbarVisualRevisions()
    local general = EnsureDB().general or {}
    if unit then
        if unit == "player" and type(_G.MSUF_ReanchorPlayerCastBarBase) == "function" then
            _G.MSUF_ReanchorPlayerCastBarBase()
        end
        return ApplyCastbarVisualsForUnit(unit, true, general)
    end

    if type(_G.MSUF_ReanchorPlayerCastBarBase) == "function" then
        _G.MSUF_ReanchorPlayerCastBarBase()
    end

    ApplyAllCastbarVisuals(general)
end
ExportPublic("MSUF_UpdateCastbarVisuals", UpdateCastbarVisuals)
ExportPublic("MSUF_UpdateCastbarVisuals_Immediate", UpdateCastbarVisuals)

local CASTBAR_SYNC_UNITS = { "player", "target", "focus", "boss" }

local function ApplyAllCastbarsAndSync()
    local general = EnsureDB().general or {}
    if type(_G.MSUF_ReanchorPlayerCastBarBase) == "function" then _G.MSUF_ReanchorPlayerCastBarBase() end
    if type(_G.MSUF_ReanchorTargetCastBarBase) == "function" then _G.MSUF_ReanchorTargetCastBarBase() end
    if type(_G.MSUF_ReanchorFocusCastBarBase) == "function" then _G.MSUF_ReanchorFocusCastBarBase() end
    if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
        _G.MSUF_ApplyBossCastbarPositionSetting(nil, true, true)
    end

    BumpCastbarVisualRevisions()
    ApplyAllCastbarVisuals(general)

    local updateEditInfo = _G.MSUF_UpdateCastbarEditInfo
    local syncPopup = _G.MSUF_SyncCastbarPositionPopup
    for index = 1, #CASTBAR_SYNC_UNITS do
        local unitKey = CASTBAR_SYNC_UNITS[index]
        if type(updateEditInfo) == "function" then updateEditInfo(unitKey) end
        if type(syncPopup) == "function" then syncPopup(unitKey) end
    end
end
ExportPublic("MSUF_ApplyAllCastbarsAndSync", ApplyAllCastbarsAndSync)

do
    local UF = MSUF and MSUF.UF
    if UF and type(UF.RegisterVisualRefreshCallback) == "function" then
        UF.RegisterVisualRefreshCallback("Castbars", function(unit)
            if unit ~= nil and unit ~= "*" then
                ApplyCastbarVisualsForUnit(unit)
            end
        end)
    end
end

MSUF.Castbars = MSUF.Castbars or {}
MSUF.Castbars._GetFontPath = GetFontPath
MSUF.Castbars._GetFontFlags = GetGlobalFontFlags
MSUF.MSUF_GetFontPath = GetFontPath
MSUF.MSUF_GetFontFlags = GetGlobalFontFlags
ExportPublic("MSUF_GetFontPath", GetFontPath)
ExportPublic("MSUF_GetFontFlags", GetGlobalFontFlags)
