-- Media, visual refresh and cold apply coordination.

local _, MSUF = ...
local Castbars = MSUF.Require("MSUF", "Castbars/MSUF_Castbars_Core.lua").Castbars
local Anchors = Castbars.Anchors
local Config = Castbars.Config
local Core = Castbars.Core
local Frames = Castbars.Frames
local KickReady = Castbars.KickReady
local Manager = Castbars.Manager
local Previews = Castbars.Previews
local PublicAPI = Castbars.PublicAPI
local Utils = Castbars.Utils
local Visuals = Castbars.Visuals

local Publish = PublicAPI.Publish
local IsSecret = MSUF.Util.IsSecret

local type = type
local tonumber = tonumber
local tostring = tostring
local math_max = math.max
local math_floor = math.floor

--- Providers that load before this file in every client TOC (State defaults,
--- Kernel, the Runtime font registry, the Edit Mode castbar popup). A missing
--- one is a load-order bug, so it fails here, loudly.
local FILE = "Castbars/MSUF_Castbars_Core.lua"
local Require = MSUF.Require
local UpdateCastbarEditInfo = Require("MSUF_UpdateCastbarEditInfo", FILE)
local SyncCastbarPositionPopup = Require("MSUF_SyncCastbarPositionPopup", FILE)
local PixelLayoutRegion = Require("MSUF_PixelLayoutRegion", FILE)
local IsInCombat = Require("MSUF_IsPlayerInCombat", FILE)

local Preview = MSUF.Require("MSUF", FILE).UF.Preview
local previewKind = type(Preview)
assert(previewKind == "table", "MSUF: missing required dependency 'UF.Preview' required by " .. FILE)
local validateKind = type(Preview.Validate)
assert(validateKind == "function", "MSUF: missing required dependency 'UF.Preview.Validate' required by " .. FILE)
Preview.Validate(FILE)
Preview.InitializeBoss()

Core.CastbarUnitInfo = Core.CastbarUnitInfo or {
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
    arena = {
        label = "Arena Castbar",
        prefix = nil,
        defaultX = 0,
        defaultY = 0,
        showTimeKey = "showArenaCastTime",
        isBoss = false,
        isArena = true,
    },
}

local function GetCastbarUnitInfo(unit)
    local info = Core.CastbarUnitInfo
    return info and info[unit] or nil
end

local function IsBossCastbarUnit(unit)
    local info = GetCastbarUnitInfo(unit)
    return (info and info.isBoss) and true or false
end

local function IsArenaCastbarUnit(unit)
    local info = GetCastbarUnitInfo(unit)
    return (info and info.isArena) and true or false
end

--- Boss and arena castbars are indexed pools (MSUF_CastbarPools.lua) with
--- indexed previews (MSUF_CastbarPoolPreviews.lua); both load after this file.
--- Every boss/arena path below goes through these lookups.
local NO_POOLS = {}

--- The pool modules in definition order (boss, then arena).
local function CastbarPools()
    local pools = MSUF.Castbars and MSUF.Castbars.Pools
    return pools and pools.order or NO_POOLS
end

--- The pool module of a castbar config key ("boss", "arena"), nil otherwise.
local function CastbarPool(kind)
    local pools = MSUF.Castbars and MSUF.Castbars.Pools
    local kinds = pools and pools.kinds
    return kind and kinds and kinds[kind] or nil
end

local function NormalizeCastbarUnit(unit)
    unit = tostring(unit or ""):lower()
    if unit:match("^boss") then return "boss" end
    if unit:match("^arena") then return "arena" end
    return GetCastbarUnitInfo(unit) and unit or nil
end

local function GetCastbarPrefix(unit)
    local info = GetCastbarUnitInfo(unit)
    return info and info.prefix or nil
end
Core.GetCastbarPrefix = GetCastbarPrefix
Publish("MSUF_GetCastbarPrefix", Core.GetCastbarPrefix)

local function GetCastbarDefaultOffsets(unit)
    local info = GetCastbarUnitInfo(unit)
    if not info then return 0, 0 end
    return info.defaultX or 0, info.defaultY or 0
end
Core.GetCastbarDefaultOffsets = GetCastbarDefaultOffsets
Publish("MSUF_GetCastbarDefaultOffsets", Core.GetCastbarDefaultOffsets)

local function GetCastbarUnitFromFrame(frame)
    if not frame then return nil end
    if Frames.Get("bossPreview", 1) and frame == Frames.Get("bossPreview", 1) then return "boss" end
    if ( Frames.player and frame == Frames.player )
        or ( Frames.playerPreview and frame == Frames.playerPreview ) then
        return "player"
    end
    if ( Frames.target and frame == Frames.target )
        or ( Frames.targetPreview and frame == Frames.targetPreview ) then
        return "target"
    end
    if ( Frames.focus and frame == Frames.focus )
        or ( Frames.focusPreview and frame == Frames.focusPreview ) then
        return "focus"
    end
    return nil
end
Core.GetCastbarUnitFromFrame = GetCastbarUnitFromFrame

local ApplyCastbarVisualsForUnit

local function ApplyCastbarUnitAndSync(unit, current)
    unit = NormalizeCastbarUnit(unit)
    if not unit then return end
    if not current then Config.Invalidate() end

    local poolKind = (IsBossCastbarUnit(unit) and "boss") or (IsArenaCastbarUnit(unit) and "arena") or nil
    if poolKind then
        local pool = CastbarPool(poolKind)
        if pool then
            pool.ApplyPositionSetting(nil, true, true)
        end
        if ApplyCastbarVisualsForUnit then
            ApplyCastbarVisualsForUnit(poolKind, nil, nil, true)
        elseif Core.UpdateCastbarVisuals then
            Core.UpdateCastbarVisuals(poolKind, true)
        end
        UpdateCastbarEditInfo(poolKind)
        SyncCastbarPositionPopup(poolKind)
        MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_ApplyCastbarUnitAndSync")
        return
    end

    if unit == "player" then
        Anchors.ReanchorPlayerCastBarBase()
    elseif unit == "target" then
        Anchors.ReanchorTargetCastBarBase()
    elseif unit == "focus" then
        Anchors.ReanchorFocusCastBarBase()
    end

    if ApplyCastbarVisualsForUnit then
        ApplyCastbarVisualsForUnit(unit, nil, nil, true)
    elseif Core.UpdateCastbarVisuals then
        Core.UpdateCastbarVisuals(unit, true)
    end
    UpdateCastbarEditInfo(unit)
    SyncCastbarPositionPopup(unit)
    MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_ApplyCastbarUnitAndSync")
end
Core.ApplyCastbarUnitAndSync = ApplyCastbarUnitAndSync
Publish("MSUF_ApplyCastbarUnitAndSync", Core.ApplyCastbarUnitAndSync)

local Media = MSUF.Media
local ResolveTextureCandidate = Media.ResolveTextureCandidate
local function EnsureDB()
    return Config.EnsureSource()
end
-- Compatibility readers retain identity; all shared policy lives in Runtime.
Core.GetFontPath = Require("MSUF_GetFontPath", FILE)
Core.GetFontFlags = Require("MSUF_GetFontFlags", FILE)
Core.GetGlobalFontSettings = Require("MSUF_GetGlobalFontSettings", FILE)
Core.GetBarTexture = Require("MSUF_GetBarTexture", FILE)
Core.GetBarBackgroundTexture = Require("MSUF_GetBarBackgroundTexture", FILE)
Core.ResolveStatusbarTextureKey = Require("MSUF_ResolveStatusbarTextureKey", FILE)
Core.ClearResolvedStatusbarTextureCache = Require("MSUF_ClearResolvedStatusbarTextureCache", FILE)
Core.BUILTIN_BAR_TEXTURES = Require("MSUF_BUILTIN_BAR_TEXTURES", FILE)
MSUF.Castbars._GetFontPath = Core.GetFontPath
MSUF.Castbars._GetFontFlags = Core.GetFontFlags

local function GetCastbarTexture()
    local db = EnsureDB()
    local general = db.general
    local castbarKey = general and general.castbarTexture or nil
    local barKey = general and general.barTexture or nil

    local cache = Core.CastbarTextureCache
    if not cache then
        cache = {}
        Core.CastbarTextureCache = cache
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
Core.GetCastbarTexture = GetCastbarTexture
Publish("MSUF_GetCastbarTexture", Core.GetCastbarTexture)

local function GetCastbarBackgroundTexture()
    local db = EnsureDB()
    local general = db.general
    local key = general and general.castbarBackgroundTexture or nil
    if key == nil or key == "" then key = general and general.castbarTexture end
    if key == nil or key == "" then key = general and general.barTexture end

    local cache = Core.CastbarBackgroundTextureCache
    if not cache then
        cache = {}
        Core.CastbarBackgroundTextureCache = cache
    end

    local cacheKey = key or ""
    local cached = cache[cacheKey]
    if cached then return cached end

    local texture, cacheable = ResolveTextureCandidate(key)
    if not texture or texture == "" then texture = "Interface\\TARGETINGFRAME\\UI-StatusBar" end
    if cacheable then cache[cacheKey] = texture end
    return texture
end
Core.GetCastbarBackgroundTexture = GetCastbarBackgroundTexture
Publish("MSUF_GetCastbarBackgroundTexture", Core.GetCastbarBackgroundTexture)

local function BumpCastbarStyleRevision()
    Config.Invalidate("texture")
    return Config.textureRevision
end

Core.BumpCastbarStyleRevision = BumpCastbarStyleRevision
Publish("MSUF_BumpCastbarStyleRevision", Core.BumpCastbarStyleRevision)

local function GetGlobalCastbarStyleCache()
    local revision = Config.textureRevision or 1
    local cache = Core.GlobalCastbarStyleCache
    if cache and cache.rev == revision then return cache end

    cache = cache or {}
    cache.rev = revision

    local texture = GetCastbarTexture()
    if not texture or texture == "" then texture = "Interface\\TARGETINGFRAME\\UI-StatusBar" end
    cache.texture = texture

    local bgTexture = GetCastbarBackgroundTexture()
    if not bgTexture or bgTexture == "" then bgTexture = texture end
    cache.bgTexture = bgTexture
    Core.GlobalCastbarStyleCache = cache
    return cache
end

local function RefreshCastbarStyleCache(frame)
    if not frame then return end

    local revision = Config.textureRevision or 1
    if frame.MSUF_castbarStyleRev == revision then return end

    local cache = GetGlobalCastbarStyleCache()
    frame.MSUF_castbarStyleRev = revision
    if cache then
        frame.MSUF_cachedCastbarTexture = cache.texture
        frame.MSUF_cachedCastbarBackgroundTexture = cache.bgTexture or cache.texture
    end
end
Core.RefreshCastbarStyleCache = RefreshCastbarStyleCache

local function ForEachCastbarFrame(callback)
    callback(Frames.player)
    callback(Frames.target)
    callback(Frames.focus)
    callback(Frames.playerPreview)
    callback(Frames.targetPreview)
    callback(Frames.focusPreview)
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
    end
    if frame and frame.backgroundBar then
        frame.backgroundBar:SetTexture(bgTexture)
        frame.MSUF_cachedCastbarBackgroundTexture = bgTexture
    end
end

local function UpdateCastbarTextures(current)
    if not current then Config.Invalidate() end
    Config.Advance("texture")
    local revision = Config.textureRevision or 1
    local texture = GetCastbarTexture()
    if not texture then return end

    local bgTexture = GetCastbarBackgroundTexture()
    if not bgTexture or bgTexture == "" then bgTexture = texture end

    ForEachCastbarFrame(function(frame)
        UpdateTextureForFrame(frame, texture, bgTexture, revision)
    end)

    local pools = CastbarPools()
    for poolIndex = 1, #pools do
        local castbars = pools[poolIndex].Castbars()
        if type(castbars) == "table" then
            for index = 1, #castbars do
                UpdateTextureForFrame(castbars[index], texture, bgTexture, revision)
            end
        end
    end
    local refreshRoundedGlow = MSUF.Castbars and MSUF.Castbars.RefreshRoundedGlow
    if refreshRoundedGlow then refreshRoundedGlow() end
end
Core.UpdateCastbarTextures = UpdateCastbarTextures
Publish("MSUF_UpdateCastbarTextures", Core.UpdateCastbarTextures)
Core.UpdateCastbarTextures_Immediate = UpdateCastbarTextures
Publish("MSUF_UpdateCastbarTextures_Immediate", Core.UpdateCastbarTextures_Immediate)

local function ApplySparkLayout(frame, statusBar, general, height)
    local enabled = general and general.castbarShowSpark == true
    local spark = frame.spark
    if enabled and not spark then
        spark = PixelLayoutRegion(statusBar:CreateTexture(nil, "OVERLAY", nil, 6))
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
            local reversed = Utils.GetCastbarReverseFillForFrame(frame, false) == true
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
Core.ApplyCastbarSparkVisual = ApplyCastbarSparkVisual

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
        local normalizer = Anchors.NormalizeCastbarWidthSource or Anchors.NormalizePlayerCastbarWidthSource
        local widthSourceKey = Anchors.GetCastbarWidthSourceKey and Anchors.GetCastbarWidthSourceKey(unit)
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
        if unit == "boss" or unit == "arena" then
            local desiredWidth, desiredHeight = Anchors.GetCastbarDesiredSize(
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
    arena = "arenaCastFrameLevelOffset",
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
Core.GetCastbarFrameLevelOffset = GetCastbarFrameLevelOffset
Publish("MSUF_GetCastbarFrameLevelOffset", Core.GetCastbarFrameLevelOffset)

local function CastbarAnchorFrame(frame, unit)
    local frameUnit = frame and tostring(frame.unit or "") or ""
    -- A pool bar carries its slot unit; a pool preview carries its slot index.
    local pool = CastbarPool(unit)
    if pool and not frameUnit:match(pool.slotUnitPattern) then
        local indexField = pool.preview and pool.preview.indexField
        frameUnit = pool.unitPrefix .. tostring(tonumber(frame and indexField and frame[indexField]) or 1)
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
    local anchorStrata
    if anchor and anchor.GetFrameStrata then anchorStrata = anchor:GetFrameStrata() end
    if IsSecret(anchorStrata) then anchorStrata = nil end
    -- The owning Unit Frame and castbar must share one strata. Otherwise WoW's
    -- strata ordering always wins and the 0-30 frame-level control cannot move
    -- the castbar behind or in front of Unit Frame content.
    local wanted = anchorStrata or ((unit == "boss" or unit == "arena") and "HIGH" or "MEDIUM")
    local currentStrata
    if frame.GetFrameStrata then currentStrata = frame:GetFrameStrata() end
    if wanted and wanted ~= "" and (IsSecret(currentStrata) or wanted ~= currentStrata) then
        frame:SetFrameStrata(wanted)
    end
end

local CASTBAR_ICON_LAYER_KEYS = {
    player = "castbarPlayerIconFrameLevelOffset",
    target = "castbarTargetIconFrameLevelOffset",
    focus = "castbarFocusIconFrameLevelOffset",
    boss = "bossCastIconFrameLevelOffset",
    arena = "arenaCastIconFrameLevelOffset",
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
Core.ResolveCastbarIconFrameLevel = ResolveCastbarIconFrameLevel

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
Core.ApplyCastbarFrameLayer = ApplyCastbarFrameLayer

local function ApplyCastbarVisualFrameCold(frame, general, forcedUnit)
    if not (frame and frame.statusBar) then return false end
    local height, width
    general, height, width = ApplyCastbarBaseGeometry(frame, general, forcedUnit)
    ApplyCastbarFrameLayer(frame, general, forcedUnit)
    local globalRevision = Config.styleRevision or 1
    local textureRevision = Config.textureRevision or 1
    if frame._msufCastbarColdGlobalRev == globalRevision
        and frame._msufCastbarColdTextureRev == textureRevision
        and frame._msufCastbarColdUnit == forcedUnit
        and frame._msufCastbarColdWidth == width
        and frame._msufCastbarColdHeight == height then
        return true
    end
    Visuals.RefreshCastbarFrame(frame, forcedUnit, general)
    -- The public entry, like the anchor and pool paths: Classic replaces it
    -- with the inner-surface spark (Game/Classic/Castbars/MSUF_CastbarVisualCompat.lua).
    Core.ApplyCastbarSparkVisual(frame, general)
    frame._msufCastbarStyleRev = globalRevision
    frame._msufCastbarColdGlobalRev = globalRevision
    frame._msufCastbarColdTextureRev = textureRevision
    frame._msufCastbarColdUnit = forcedUnit
    frame._msufCastbarColdWidth = width
    frame._msufCastbarColdHeight = height
    return true
end

local function BumpCastbarVisualRevisions()
    Config.Advance("texture")

    local bumpStyle = Manager.BumpCastbarStyleRev
    if type(bumpStyle) == "function" then bumpStyle() end

    local bumpTime = Manager.BumpCastTimeRev
    if type(bumpTime) == "function" then bumpTime() end
end

--- The live bars of one pool.
local function ApplyPoolRuntimeVisuals(pool, general)
    local did = false
    local kind = pool.kind
    local castbars = pool.Castbars()
    local framePrefix = pool.descriptor.framePrefix
    for index = 1, pool.maxFrames do
        local frame = (castbars and castbars[index]) or _G[framePrefix .. index]
        did = ApplyCastbarVisualFrameCold(frame, general, kind) or did
    end
    return did
end

-- The preview refresh re-enters Core through the preview layout; one lock per
-- pool kind stops that recursion.
local poolPreviewRefreshLocked = {}
-- Boss re-runs its Edit Mode preview setup after a refresh (the Retail
-- behaviour); arena never did.
local SETUP_AFTER_PREVIEW_REFRESH = { boss = "SetupBossCastbarPreviewEditMode" }

--- Rebuilds the pool's previews out of combat, or restyles the ones that exist
--- while the preview module is missing or busy.
local function RefreshPoolPreviews(pool, general)
    if IsInCombat() then return false end

    local kind = pool.kind
    local preview = pool.preview
    if preview and not poolPreviewRefreshLocked[kind] then
        poolPreviewRefreshLocked[kind] = true
        preview:Update()
        local setupName = SETUP_AFTER_PREVIEW_REFRESH[kind]
        local setupEditMode = setupName and Previews[setupName]
        if type(setupEditMode) == "function" then setupEditMode() end
        poolPreviewRefreshLocked[kind] = false
        return true
    end

    local did = false
    if preview then
        for index = 1, preview.maxFrames do
            did = ApplyCastbarVisualFrameCold(Frames.Get(preview.frameKind, index), general, kind) or did
        end
    end
    return did
end

ApplyCastbarVisualsForUnit = function(unit, revisionsReady, general, current)
    if IsBossCastbarUnit(unit) then
        unit = "boss"
    elseif IsArenaCastbarUnit(unit) then
        unit = "arena"
    else
        unit = tostring(unit or "")
    end
    if not revisionsReady then
        if not current then Config.Invalidate() end
        BumpCastbarVisualRevisions()
    end
    general = general or EnsureDB().general or {}
    local did = false
    if unit == "player" then
        did = ApplyCastbarVisualFrameCold(Frames.player, general, unit) or did
        if not IsInCombat() then did = ApplyCastbarVisualFrameCold(Frames.playerPreview, general, unit) or did end
    elseif unit == "target" then
        did = ApplyCastbarVisualFrameCold(Frames.target, general, unit) or did
        if not IsInCombat() then did = ApplyCastbarVisualFrameCold(Frames.targetPreview, general, unit) or did end
    elseif unit == "focus" then
        did = ApplyCastbarVisualFrameCold(Frames.focus, general, unit) or did
        if not IsInCombat() then did = ApplyCastbarVisualFrameCold(Frames.focusPreview, general, unit) or did end
    else
        local pool = CastbarPool(unit)
        if pool then
            did = ApplyPoolRuntimeVisuals(pool, general) or did
            did = RefreshPoolPreviews(pool, general) or did
        end
    end
    MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_ApplyCastbarVisualsForUnit")
    return did
end
Core.ApplyCastbarVisualsForUnit = ApplyCastbarVisualsForUnit
Publish("MSUF_ApplyCastbarVisualsForUnit", Core.ApplyCastbarVisualsForUnit)

local function ApplyAllCastbarVisuals(general)
    ApplyCastbarVisualFrameCold(Frames.player, general, "player")
    ApplyCastbarVisualFrameCold(Frames.target, general, "target")
    ApplyCastbarVisualFrameCold(Frames.focus, general, "focus")

    if not IsInCombat() then
        ApplyCastbarVisualFrameCold(Frames.playerPreview, general, "player")
        ApplyCastbarVisualFrameCold(Frames.targetPreview, general, "target")
        ApplyCastbarVisualFrameCold(Frames.focusPreview, general, "focus")
    end

    local pools = CastbarPools()
    for index = 1, #pools do
        ApplyPoolRuntimeVisuals(pools[index], general)
        RefreshPoolPreviews(pools[index], general)
    end
end

local function UpdateCastbarVisuals(unit, current)
    if not current then Config.Invalidate() end
    unit = NormalizeCastbarUnit(unit)
    BumpCastbarVisualRevisions()
    local general = EnsureDB().general or {}
    if unit then
        if unit == "player" then
            Anchors.ReanchorPlayerCastBarBase()
        end
        local result = ApplyCastbarVisualsForUnit(unit, true, general)
        MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_UpdateCastbarVisuals")
        return result
    end

    Anchors.ReanchorPlayerCastBarBase()

    ApplyAllCastbarVisuals(general)
    MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_UpdateCastbarVisuals")
end
Core.UpdateCastbarVisuals = UpdateCastbarVisuals
Publish("MSUF_UpdateCastbarVisuals", Core.UpdateCastbarVisuals)
Core.UpdateCastbarVisuals_Immediate = UpdateCastbarVisuals
Publish("MSUF_UpdateCastbarVisuals_Immediate", Core.UpdateCastbarVisuals_Immediate)

local CASTBAR_SYNC_UNITS = { "player", "target", "focus", "boss", "arena" }

local function ApplyAllCastbarsAndSync(current)
    if not current then Config.Invalidate() end
    local general = EnsureDB().general or {}
    Anchors.ReanchorPlayerCastBarBase()
    Anchors.ReanchorTargetCastBarBase()
    Anchors.ReanchorFocusCastBarBase()
    local pools = CastbarPools()
    for index = 1, #pools do
        pools[index].ApplyPositionSetting(nil, true, true)
    end

    BumpCastbarVisualRevisions()
    ApplyAllCastbarVisuals(general)

    for index = 1, #CASTBAR_SYNC_UNITS do
        local unitKey = CASTBAR_SYNC_UNITS[index]
        UpdateCastbarEditInfo(unitKey)
        SyncCastbarPositionPopup(unitKey)
    end
    -- Castbars/MSUF_InterruptReady.lua: consumers of the interrupt indicator's
    -- look (the MSUF Suite's nameplates) redraw from the settings just applied.
    KickReady.KickReady_NotifySettings(true)
end
Core.ApplyAllCastbarsAndSync = ApplyAllCastbarsAndSync
Publish("MSUF_ApplyAllCastbarsAndSync", Core.ApplyAllCastbarsAndSync)

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
