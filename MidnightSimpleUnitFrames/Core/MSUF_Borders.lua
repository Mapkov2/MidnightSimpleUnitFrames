-- Core/MSUF_Borders.lua  Aggro / Dispel / Purge border system + UI_SCALE handler
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...

local F = ns.Cache and ns.Cache.F or {}
F.CreateFrame = F.CreateFrame or CreateFrame
local type, tonumber, ipairs, pairs = type, tonumber, ipairs, pairs
local math_floor, math_ceil = math.floor, math.ceil
local MSUF_TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"
local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax

local function _MSUF_BorderEffectiveScale(region)
    if region and region.GetEffectiveScale then
        local scale = region:GetEffectiveScale()
        if scale and scale > 0 then return scale end
    end
    local parent = _G.UIParent
    if parent and parent.GetEffectiveScale then
        local scale = parent:GetEffectiveScale()
        if scale and scale > 0 then return scale end
    end
    return 1
end

local function _MSUF_BorderPixelToUIUnitFactor()
    local getSize = _G.GetPhysicalScreenSize
    if type(getSize) == "function" then
        local _, physicalHeight = getSize()
        physicalHeight = tonumber(physicalHeight) or 0
        if physicalHeight > 0 then
            return 768 / physicalHeight
        end
    end
    return 1
end

local function _MSUF_BorderPixelSize(region, value, minPixels)
    value = tonumber(value) or 0
    if value == 0 then return 0 end

    local scale = _MSUF_BorderEffectiveScale(region)
    local pixelUtil = _G.PixelUtil
    if pixelUtil and type(pixelUtil.GetNearestPixelSize) == "function" then
        local size = pixelUtil.GetNearestPixelSize(value, scale, minPixels)
        if size and size ~= 0 then
            return size
        end
    end

    local factor = _MSUF_BorderPixelToUIUnitFactor()
    if factor <= 0 or scale <= 0 then
        return value
    end

    local pixels = value * scale / factor
    if pixels >= 0 then
        pixels = math_floor(pixels + 0.5)
    else
        pixels = math_ceil(pixels - 0.5)
    end

    minPixels = tonumber(minPixels) or 0
    if minPixels > 0 then
        if pixels == 0 then
            pixels = (value < 0) and -minPixels or minPixels
        elseif pixels > 0 and pixels < minPixels then
            pixels = minPixels
        elseif pixels < 0 and pixels > -minPixels then
            pixels = -minPixels
        end
    end

    return pixels * factor / scale
end

local function _MSUF_BorderDisableSnap(region)
    if not region then return end
    if region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
    end
    if region.SetTexelSnappingBias then
        region:SetTexelSnappingBias(0)
    end
end

local function _MSUF_BorderSetPoint(region, ...)
    if not region then return end
    local pixelUtil = _G.PixelUtil
    if pixelUtil and type(pixelUtil.SetPoint) == "function" then
        pixelUtil.SetPoint(region, ...)
    elseif region.SetPoint then
        region:SetPoint(...)
    end
end

local function _MSUF_BorderSetHeight(region, height)
    if not region then return end
    local pixelUtil = _G.PixelUtil
    if pixelUtil and type(pixelUtil.SetHeight) == "function" then
        pixelUtil.SetHeight(region, height)
    elseif region.SetHeight then
        region:SetHeight(height)
    end
end

local function _MSUF_BorderSetWidth(region, width)
    if not region then return end
    local pixelUtil = _G.PixelUtil
    if pixelUtil and type(pixelUtil.SetWidth) == "function" then
        pixelUtil.SetWidth(region, width)
    elseif region.SetWidth then
        region:SetWidth(width)
    end
end

local function _MSUF_TestModeCombatLocked()
    return _G.MSUF_InCombat == true or ((InCombatLockdown and InCombatLockdown()) and true or false)
end

local function _MSUF_RefreshBorderTestModesActive()
    local active = (not _MSUF_TestModeCombatLocked())
        and (_G.MSUF_AggroBorderTestMode == true
            or _G.MSUF_DispelBorderTestMode == true
            or _G.MSUF_PurgeBorderTestMode == true
            or _G.MSUF_BossTargetBorderTestMode == true)
    _G.MSUF_BorderTestModesActive = active and true or false
    return _G.MSUF_BorderTestModesActive
end

local function _MSUF_EnableBorderTestMode(active)
    if active and _MSUF_TestModeCombatLocked() then
        return false
    end
    return active and true or false
end

_G.MSUF_ClearBorderTestModesForCombat = _G.MSUF_ClearBorderTestModesForCombat or function()
    _G.MSUF_AggroBorderTestMode = false
    _G.MSUF_DispelBorderTestMode = false
    _G.MSUF_PurgeBorderTestMode = false
    _G.MSUF_BossTargetBorderTestMode = false
    _G.MSUF_BorderTestModesActive = false
end
_G.MSUF_RefreshBorderTestModesActive = _G.MSUF_RefreshBorderTestModesActive or _MSUF_RefreshBorderTestModesActive

local _FRIENDLY_DISPEL_CLASS = {
    DRUID = true,
    EVOKER = true,
    MAGE = true,
    MONK = true,
    PALADIN = true,
    PRIEST = true,
    SHAMAN = true,
}
local _PURGE_CLASS = {
    DEMONHUNTER = true,
    HUNTER = true,
    MAGE = true,
    PRIEST = true,
    SHAMAN = true,
    WARLOCK = true,
}
local _playerFriendlyDispelCapable
local _playerPurgeCapable

local function PlayerMayFriendlyDispel()
    if _playerFriendlyDispelCapable ~= nil then
        return _playerFriendlyDispelCapable
    end

    local class
    if UnitClass then
        local _, classToken = UnitClass("player")
        class = classToken
    end
    if not class then
        return true
    end

    _playerFriendlyDispelCapable = (_FRIENDLY_DISPEL_CLASS[class] == true)
    return _playerFriendlyDispelCapable
end

local function PlayerMayPurge()
    if _playerPurgeCapable ~= nil then
        return _playerPurgeCapable
    end

    local class
    if UnitClass then
        local _, classToken = UnitClass("player")
        class = classToken
    end
    if not class then
        return true
    end

    local race
    if UnitRace then
        local _, raceToken = UnitRace("player")
        race = raceToken
    end
    _playerPurgeCapable = (_PURGE_CLASS[class] == true) or (race == "BloodElf")
    return _playerPurgeCapable
end

local function ClearFriendlyDispelCapabilityCache()
    _playerFriendlyDispelCapable = nil
    _playerPurgeCapable = nil
end

-- From main file (exported to _G)
local MSUF_ForEachUnitFrame = _G.MSUF_ForEachUnitFrame
local MSUF_GetDesiredBarBorderThicknessAndStamp = _G.MSUF_GetDesiredBarBorderThicknessAndStamp
local MSUF_BarBorderCache = _G.MSUF_BarBorderCache
local MSUF_EventBus_Register = _G.MSUF_EventBus_Register
local MSUF_EventBus_Unregister = _G.MSUF_EventBus_Unregister

local _borderCfg = { serial = -1 }

-- LibCustomGlow for dispel glow effect
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

------------------------------------------------------------------------
-- Dispel glow helpers (UF) — zero-alloc color table reuse
------------------------------------------------------------------------
local _glowColorTbl = { 0, 0, 0, 1 }
local _procGlowOptions = { color = _glowColorTbl, key = "msufDispel" }

local function _StopDispelGlowOn(anchor)
    if not (LCG and anchor) then return end
    LCG.PixelGlow_Stop(anchor, "msufDispel")
    LCG.AutoCastGlow_Stop(anchor, "msufDispel")
    LCG.ProcGlow_Stop(anchor, "msufDispel")
end

local function _StartDispelGlow(frame, r, g, b, cfg)
    if not LCG then return end
    local anchor = frame._msufRoundedHighlightGlowAnchor
        or frame._msufHighlightDispelOutline
        or frame._msufHighlightOutline
        or frame
    local style = cfg.dispelGlowStyle or "PIXEL"
    local lines = cfg.dispelGlowLines
    local freq = cfg.dispelGlowFreq
    local thick = cfg.dispelGlowThick
    local secretColor = issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b))
    if not secretColor
        and frame._msufDispelGlowActive == true
        and frame._msufDispelGlowAnchor == anchor
        and frame._msufDispelGlowStyle == style
        and frame._msufDispelGlowR == r
        and frame._msufDispelGlowG == g
        and frame._msufDispelGlowB == b
        and frame._msufDispelGlowLines == lines
        and frame._msufDispelGlowFreq == freq
        and frame._msufDispelGlowThick == thick
    then
        return
    end
    local oldAnchor = frame._msufDispelGlowAnchor
    if oldAnchor and (oldAnchor ~= anchor or frame._msufDispelGlowStyle ~= style) then
        _StopDispelGlowOn(oldAnchor)
    end
    if anchor ~= frame then
        _StopDispelGlowOn(frame)
    end
    _glowColorTbl[1], _glowColorTbl[2], _glowColorTbl[3] = r, g, b
    if style == "AUTOCAST" then
        LCG.AutoCastGlow_Start(anchor, _glowColorTbl, lines, freq, nil, nil, nil, "msufDispel")
    elseif style == "PROC" then
        LCG.ProcGlow_Start(anchor, _procGlowOptions)
    else -- PIXEL default
        LCG.PixelGlow_Start(anchor, _glowColorTbl, lines, freq, nil, thick, nil, nil, nil, "msufDispel")
    end
    frame._msufDispelGlowActive = true
    frame._msufDispelGlowAnchor = anchor
    frame._msufDispelGlowStyle = style
    if not secretColor then
        frame._msufDispelGlowR = r
        frame._msufDispelGlowG = g
        frame._msufDispelGlowB = b
    else
        frame._msufDispelGlowR = nil
        frame._msufDispelGlowG = nil
        frame._msufDispelGlowB = nil
    end
    frame._msufDispelGlowLines = lines
    frame._msufDispelGlowFreq = freq
    frame._msufDispelGlowThick = thick
end

local function _StopDispelGlow(frame)
    if not frame then return end
    if not frame._msufDispelGlowActive
        and not frame._msufDispelGlowAnchor
        and not frame._msufDispelGlowStyle
    then
        return
    end
    frame._msufDispelGlowActive = nil
    local anchor = frame._msufDispelGlowAnchor
    frame._msufDispelGlowAnchor = nil
    frame._msufDispelGlowStyle = nil
    frame._msufDispelGlowR = nil
    frame._msufDispelGlowG = nil
    frame._msufDispelGlowB = nil
    frame._msufDispelGlowLines = nil
    frame._msufDispelGlowFreq = nil
    frame._msufDispelGlowThick = nil
    _StopDispelGlowOn(anchor)

    local outlines = frame._msufHighlightOutlines
    if outlines then
        for _, outline in pairs(outlines) do
            if outline and outline ~= anchor then
                _StopDispelGlowOn(outline)
            end
        end
    else
        local outline = frame._msufHighlightOutline
        if outline and outline ~= anchor then
            _StopDispelGlowOn(outline)
        end
    end
    if frame ~= anchor then
        _StopDispelGlowOn(frame)
    end
end
local function _Clamp01(v, def)
    if type(v) ~= "number" then return def end
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

local function _OutlineModeToNumber(value, fallback)
    if value == true then return 1 end
    if value == false then return 0 end
    local n = tonumber(value)
    if n ~= nil then return (n == 1) and 1 or 0 end
    return fallback
end

local function _ReadOutlineMode(db, key, legacyKey, fallback)
    if db and db[key] ~= nil then
        return _OutlineModeToNumber(db[key], fallback)
    end
    if legacyKey and db and db[legacyKey] ~= nil then
        return _OutlineModeToNumber(db[legacyKey], fallback)
    end
    return fallback
end

local function _ReadColorValue(db, key, legacyKey, fallback)
    local value = db and db[key]
    if type(value) ~= "number" and legacyKey then
        if type(legacyKey) == "table" then
            for i = 1, #legacyKey do
                value = db and db[legacyKey[i]]
                if type(value) == "number" then break end
            end
        else
            value = db and db[legacyKey]
        end
    end
    return _Clamp01(value, fallback)
end

local function _BoolEnabled(value)
    return value == true or value == 1
end

local UF_LAYER_DISPEL_OVERLAY = 6
local UF_LAYER_HIGHLIGHT = 10
local _SyncUFFrameLayerAbove = _G.MSUF_SyncFrameLayerAbove

local DISPEL_TRIGGER_BY_ME = "BY_ME"
local DISPEL_TRIGGER_TYPE = "DISPEL_TYPE"
local DISPEL_TRIGGER_ANY = "ANY_DEBUFF"
local DISPEL_TRIGGER_BORDER = "BORDER"

local function _NormalizeDispelBorderTrigger(value)
    if value == DISPEL_TRIGGER_TYPE or value == "TYPE" or value == "TYPED" or value == "ANY_DISPEL_TYPE" then
        return DISPEL_TRIGGER_TYPE
    end
    if value == DISPEL_TRIGGER_ANY or value == "ANY" or value == "ALL" or value == "ALL_DEBUFFS" then
        return DISPEL_TRIGGER_ANY
    end
    return DISPEL_TRIGGER_BY_ME
end

local function _NormalizeUnitDispelOverlayTrigger(value)
    if value == DISPEL_TRIGGER_BORDER or value == "INHERIT" or value == "SAME" or value == "BORDER_DETECTS" then
        return DISPEL_TRIGGER_BORDER
    end
    return _NormalizeDispelBorderTrigger(value)
end

local function _ResolveUnitDispelOverlayTrigger(cfg)
    local trigger = _NormalizeUnitDispelOverlayTrigger(cfg and cfg.unitDispelOverlayTrigger)
    if trigger == DISPEL_TRIGGER_BORDER then
        return _NormalizeDispelBorderTrigger(cfg and cfg.dispelBorderTrigger)
    end
    return trigger
end

local function _DispelBorderTriggerNeedsPlayerDispel(value)
    local trigger = _NormalizeDispelBorderTrigger(value)
    return trigger == DISPEL_TRIGGER_BY_ME
end

local function _UnitCanReceiveFriendlyDispelVisual(unit)
    if unit == "player" then return true end
    return UnitCanAssist and UnitCanAssist("player", unit)
end

local _ResolveUnitFrame, _RefreshBorderSettingsForFrame, _UFDispelScanCustomTypePriorityEnabled

local function _UnitCanScanDispelTriggerVisual(unit, triggerMode, cfg, useOverlayPriority)
    triggerMode = _NormalizeDispelBorderTrigger(triggerMode)
    if triggerMode == DISPEL_TRIGGER_BY_ME then
        if not cfg then
            local uf = _ResolveUnitFrame(unit)
            cfg = uf and _RefreshBorderSettingsForFrame(uf)
        end
        if _UFDispelScanCustomTypePriorityEnabled and _UFDispelScanCustomTypePriorityEnabled(cfg, useOverlayPriority) then
            if unit == "player" then return true end
            return not UnitExists or UnitExists(unit)
        end
        return _UnitCanReceiveFriendlyDispelVisual(unit) and PlayerMayFriendlyDispel()
    end
    if unit == "player" then return true end
    return not UnitExists or UnitExists(unit)
end

_ResolveUnitFrame = function(unit)
    if type(unit) ~= "string" or unit == "" then return nil end
    local frames = _G.MSUF_UnitFrames
    local frame = type(frames) == "table" and frames[unit] or nil
    if frame then return frame end
    return _G["MSUF_" .. unit]
end

local function _FrameMatchesUnit(frame, unit)
    if not frame or type(unit) ~= "string" then return false end
    return frame.unit == unit or frame == _G["MSUF_" .. unit]
end

_G.MSUF_NormalizeDispelBorderTrigger = _G.MSUF_NormalizeDispelBorderTrigger or _NormalizeDispelBorderTrigger
_G.MSUF_DispelBorderTriggerNeedsPlayerDispel = _G.MSUF_DispelBorderTriggerNeedsPlayerDispel or _DispelBorderTriggerNeedsPlayerDispel
_G.MSUF_NormalizeUnitDispelOverlayTrigger = _G.MSUF_NormalizeUnitDispelOverlayTrigger or _NormalizeUnitDispelOverlayTrigger

local function _NormalizeBorderScope(unit)
    if type(unit) ~= "string" or unit == "" then return "shared" end
    if unit == "boss" or unit:sub(1, 4) == "boss" then return "boss" end
    return unit
end

local function _GetUnitBorderScopeDB(unit)
    local scope = _NormalizeBorderScope(unit)
    if scope == "shared" then return nil, scope end
    local db = MSUF_DB and MSUF_DB[scope]
    if type(db) == "table" and db.hlOverride == true then
        return db, scope
    end
    return nil, scope
end

local function _RefreshBorderSettingsCache()
    local serial = _G.MSUF_UFCORE_SETTINGS_SERIAL or 0
    if _borderCfg.serial == serial then return _borderCfg end
    _borderCfg.serial = serial

    local g = (MSUF_DB and MSUF_DB.general) or nil
    _borderCfg.aggroOutlineMode = _ReadOutlineMode(g, "aggroOutlineMode", "hlAggroEnabled", 0)
    _borderCfg.dispelOutlineMode = _ReadOutlineMode(g, "dispelOutlineMode", "hlDispelEnabled", 1)
    _borderCfg.purgeOutlineMode = _ReadOutlineMode(g, "purgeOutlineMode", nil, 0)
    _borderCfg.bossTargetOutlineMode = _ReadOutlineMode(g, "bossTargetOutlineMode", nil, ((g and g.bossTargetHighlightEnabled ~= false) and 1 or 0))
    _borderCfg.highlightBorderThickness = tonumber(g and g.highlightBorderThickness) or 2
    if _borderCfg.highlightBorderThickness < 1 then _borderCfg.highlightBorderThickness = 1 end
    _borderCfg.dispelBorderTrigger = _NormalizeDispelBorderTrigger(g and g.dispelBorderTrigger)
    _borderCfg.unitDispelOverlayEnabled = g and g.unitDispelOverlayEnabled == true
    _borderCfg.unitDispelOverlayStyle = (g and g.unitDispelOverlayStyle) or "FULL"
    _borderCfg.unitDispelOverlayOnHealth = not (g and g.unitDispelOverlayOnHealth == false)
    _borderCfg.unitDispelOverlayAlpha = tonumber(g and g.unitDispelOverlayAlpha) or 0.35
    if _borderCfg.unitDispelOverlayAlpha < 0 then
        _borderCfg.unitDispelOverlayAlpha = 0
    elseif _borderCfg.unitDispelOverlayAlpha > 1 then
        _borderCfg.unitDispelOverlayAlpha = 1
    end
    _borderCfg.unitDispelOverlayTrigger = _NormalizeUnitDispelOverlayTrigger(g and g.unitDispelOverlayTrigger)
    _borderCfg.dispelColorMode = (g and g.hlDispelColorMode) or "SINGLE"
    local prioEnabled = g and g.hlPrioEnabled
    if prioEnabled == nil then prioEnabled = g and (g.highlightPrioEnabled == 1) end
    _borderCfg.highlightPrioEnabled = _BoolEnabled(prioEnabled)
    _borderCfg.highlightPrioOrder = (g and type(g.hlPrioOrder) == "table" and g.hlPrioOrder)
        or (g and type(g.highlightPrioOrder) == "table" and g.highlightPrioOrder)
        or nil
    _borderCfg.aggroR  = _ReadColorValue(g, "hlAggroColorR",  { "aggroBorderColorR", "aggroBorderR" },  1.00)
    _borderCfg.aggroG  = _ReadColorValue(g, "hlAggroColorG",  { "aggroBorderColorG", "aggroBorderG" },  0.50)
    _borderCfg.aggroB  = _ReadColorValue(g, "hlAggroColorB",  { "aggroBorderColorB", "aggroBorderB" },  0.00)
    _borderCfg.dispelR = _ReadColorValue(g, "hlDispelColorR", "dispelBorderColorR", 0.25)
    _borderCfg.dispelG = _ReadColorValue(g, "hlDispelColorG", "dispelBorderColorG", 0.75)
    _borderCfg.dispelB = _ReadColorValue(g, "hlDispelColorB", "dispelBorderColorB", 1.00)
    _borderCfg.purgeR  = _ReadColorValue(g, "hlPurgeColorR",  "purgeBorderColorR",  1.00)
    _borderCfg.purgeG  = _ReadColorValue(g, "hlPurgeColorG",  "purgeBorderColorG",  0.85)
    _borderCfg.purgeB  = _ReadColorValue(g, "hlPurgeColorB",  "purgeBorderColorB",  0.00)
    local btc = g and g.bossTargetHighlightColor
    _borderCfg.bossTargetR = _Clamp01(type(btc) == "table" and btc[1], 1.00)
    _borderCfg.bossTargetG = _Clamp01(type(btc) == "table" and btc[2], 0.82)
    _borderCfg.bossTargetB = _Clamp01(type(btc) == "table" and btc[3], 0.00)
    -- Dispel glow settings
    _borderCfg.dispelGlowEnabled = (g and g.hlDispelGlowEnabled) and true or false
    _borderCfg.dispelGlowStyle   = (g and g.hlDispelGlowStyle) or "PIXEL"
    _borderCfg.dispelGlowLines   = tonumber(g and g.hlDispelGlowLines) or 8
    _borderCfg.dispelGlowFreq    = tonumber(g and g.hlDispelGlowFrequency) or 0.25
    _borderCfg.dispelGlowThick   = tonumber(g and g.hlDispelGlowThickness) or 2
    return _borderCfg
end

local _scopedBorderCfg = {}
local _BORDER_CFG_FIELDS = {
    "aggroOutlineMode",
    "dispelOutlineMode",
    "purgeOutlineMode",
    "bossTargetOutlineMode",
    "highlightBorderThickness",
    "dispelBorderTrigger",
    "unitDispelOverlayEnabled",
    "unitDispelOverlayStyle",
    "unitDispelOverlayOnHealth",
    "unitDispelOverlayAlpha",
    "unitDispelOverlayTrigger",
    "dispelColorMode",
    "highlightPrioEnabled",
    "highlightPrioOrder",
    "aggroR", "aggroG", "aggroB",
    "dispelR", "dispelG", "dispelB",
    "purgeR", "purgeG", "purgeB",
    "bossTargetR", "bossTargetG", "bossTargetB",
    "dispelGlowEnabled",
    "dispelGlowStyle",
    "dispelGlowLines",
    "dispelGlowFreq",
    "dispelGlowThick",
}

local function _CopyBorderCfg(dst, src)
    for i = 1, #_BORDER_CFG_FIELDS do
        local key = _BORDER_CFG_FIELDS[i]
        dst[key] = src[key]
    end
    return dst
end

_RefreshBorderSettingsForFrame = function(frame)
    local base = _RefreshBorderSettingsCache()
    local db = _GetUnitBorderScopeDB(frame and frame.unit)
    if not db then return base end

    local serial = base and base.serial or 0
    if frame then
        local cached = frame._msufScopedBorderCfg
        if cached
            and frame._msufScopedBorderCfgSerial == serial
            and frame._msufScopedBorderCfgUnit == frame.unit
        then
            return cached
        end
    end

    local cfg = frame and (frame._msufScopedBorderCfg or {}) or _scopedBorderCfg
    _CopyBorderCfg(cfg, base)
    cfg.serial = serial
    cfg.aggroOutlineMode = _ReadOutlineMode(db, "aggroOutlineMode", "hlAggroEnabled", base.aggroOutlineMode)
    cfg.dispelOutlineMode = _ReadOutlineMode(db, "dispelOutlineMode", "hlDispelEnabled", base.dispelOutlineMode)
    cfg.purgeOutlineMode = _ReadOutlineMode(db, "purgeOutlineMode", nil, base.purgeOutlineMode)
    cfg.bossTargetOutlineMode = _ReadOutlineMode(db, "bossTargetOutlineMode", nil, base.bossTargetOutlineMode)

    cfg.highlightBorderThickness = tonumber(db.highlightBorderThickness or db.hlAggroSize) or base.highlightBorderThickness
    if cfg.highlightBorderThickness < 1 then cfg.highlightBorderThickness = 1 end
    cfg.dispelBorderTrigger = _NormalizeDispelBorderTrigger(db.dispelBorderTrigger or base.dispelBorderTrigger)
    if db.unitDispelOverlayEnabled ~= nil then cfg.unitDispelOverlayEnabled = db.unitDispelOverlayEnabled == true end
    cfg.unitDispelOverlayStyle = db.unitDispelOverlayStyle or cfg.unitDispelOverlayStyle
    if db.unitDispelOverlayOnHealth ~= nil then cfg.unitDispelOverlayOnHealth = db.unitDispelOverlayOnHealth ~= false end
    cfg.unitDispelOverlayAlpha = tonumber(db.unitDispelOverlayAlpha) or cfg.unitDispelOverlayAlpha
    if cfg.unitDispelOverlayAlpha < 0 then
        cfg.unitDispelOverlayAlpha = 0
    elseif cfg.unitDispelOverlayAlpha > 1 then
        cfg.unitDispelOverlayAlpha = 1
    end
    cfg.unitDispelOverlayTrigger = _NormalizeUnitDispelOverlayTrigger(db.unitDispelOverlayTrigger or cfg.unitDispelOverlayTrigger)
    cfg.dispelColorMode = db.hlDispelColorMode or base.dispelColorMode

    if db.hlPrioEnabled ~= nil then
        cfg.highlightPrioEnabled = _BoolEnabled(db.hlPrioEnabled)
    elseif db.highlightPrioEnabled ~= nil then
        cfg.highlightPrioEnabled = (db.highlightPrioEnabled == 1 or db.highlightPrioEnabled == true)
    end
    if type(db.hlPrioOrder) == "table" then
        cfg.highlightPrioOrder = db.hlPrioOrder
    elseif type(db.highlightPrioOrder) == "table" then
        cfg.highlightPrioOrder = db.highlightPrioOrder
    end

    cfg.aggroR  = _ReadColorValue(db, "hlAggroColorR",  { "aggroBorderColorR", "aggroBorderR" },  base.aggroR)
    cfg.aggroG  = _ReadColorValue(db, "hlAggroColorG",  { "aggroBorderColorG", "aggroBorderG" },  base.aggroG)
    cfg.aggroB  = _ReadColorValue(db, "hlAggroColorB",  { "aggroBorderColorB", "aggroBorderB" },  base.aggroB)
    cfg.dispelR = _ReadColorValue(db, "hlDispelColorR", "dispelBorderColorR", base.dispelR)
    cfg.dispelG = _ReadColorValue(db, "hlDispelColorG", "dispelBorderColorG", base.dispelG)
    cfg.dispelB = _ReadColorValue(db, "hlDispelColorB", "dispelBorderColorB", base.dispelB)
    cfg.purgeR  = _ReadColorValue(db, "hlPurgeColorR",  "purgeBorderColorR",  base.purgeR)
    cfg.purgeG  = _ReadColorValue(db, "hlPurgeColorG",  "purgeBorderColorG",  base.purgeG)
    cfg.purgeB  = _ReadColorValue(db, "hlPurgeColorB",  "purgeBorderColorB",  base.purgeB)

    if db.hlDispelGlowEnabled ~= nil then cfg.dispelGlowEnabled = db.hlDispelGlowEnabled == true end
    cfg.dispelGlowStyle = db.hlDispelGlowStyle or cfg.dispelGlowStyle
    cfg.dispelGlowLines = tonumber(db.hlDispelGlowLines) or cfg.dispelGlowLines
    cfg.dispelGlowFreq = tonumber(db.hlDispelGlowFrequency) or cfg.dispelGlowFreq
    cfg.dispelGlowThick = tonumber(db.hlDispelGlowThickness) or cfg.dispelGlowThick
    if frame then
        frame._msufScopedBorderCfg = cfg
        frame._msufScopedBorderCfgSerial = serial
        frame._msufScopedBorderCfgUnit = frame.unit
    end
    return cfg
end

local function _OutlineModeEnabledForUnit(unit, key, legacyKey)
    local db = _GetUnitBorderScopeDB(unit)
    local base = _RefreshBorderSettingsCache()
    if db then
        return _ReadOutlineMode(db, key, legacyKey, base[key]) == 1
    end
    return base and base[key] == 1
end

local _borderIterState = {}
local MSUF_ApplyRareVisuals
local MSUF_RefreshStaticUnitFrameOutlines

local function _Iter_SyncBorderStamps(uf)
    if not uf or not uf.unit then return end
    local stamp = 0
    local get = MSUF_GetDesiredBarBorderThicknessAndStamp
    if type(get) == "function" then
        stamp = select(2, get(uf))
    end
    uf._msufBarBorderStamp = stamp
    uf._msufBarOutlineEdgeSize = -1
    uf._msufHighlightEdgeSize = -1
    uf._msufHighlightColorKey = -1
    uf._msufHighlightBottomIsPower = nil
    local pb = uf.targetPowerBar
    local pbDetached = uf._msufPowerBarDetached
    uf._msufBarOutlineBottomIsPower = (pb and not pbDetached and pb.IsShown and pb:IsShown()) and true or false
    if type(MSUF_RefreshStaticUnitFrameOutlines) == "function" then
        MSUF_RefreshStaticUnitFrameOutlines(uf)
    end
end

local function _Iter_ResetBorderOnScale(uf)
    if uf and uf.unit then
        uf._msufBarBorderStamp = nil
        uf._msufBarOutlineEdgeSize = -1
        uf._msufHighlightEdgeSize = -1
        uf._msufHighlightColorKey = -1
        if type(MSUF_RefreshStaticUnitFrameOutlines) == "function" then
            MSUF_RefreshStaticUnitFrameOutlines(uf)
        end
        if type(MSUF_ApplyRareVisuals) == "function" then
            MSUF_ApplyRareVisuals(uf)
        end
    end
end

-- Aggro outline indicator: reuse the bar-outline border and recolor/thicken it
-- when the player has threat on player/target/focus/boss frames.
local function MSUF_IsAggroOutlineUnit(unit)
    if unit == "player" then return true end
    if unit == "target" or unit == "focus" then return true end
    if type(unit) == "string" and unit:sub(1, 4) == "boss" then
        local n = tonumber(unit:sub(5))
        if n and n >= 1 and n <= 5 then return true end
    end
    return false
end

local function MSUF_GetAggroThreatSituation(unit)
    if not UnitThreatSituation then return nil end
    if unit == "player" then
        local raw = UnitThreatSituation("player", "target")
        if raw ~= nil then return raw end
        return UnitThreatSituation("player")
    end
    return UnitThreatSituation("player", unit)
end
local _UF_DISPEL_INDEX_BY_NAME = { Magic = 1, Curse = 2, Disease = 3, Poison = 4, Bleed = 5, None = 0 }
local _UF_DEBUFF_COLOR_BY_INDEX = {
    [1] = _G.DEBUFF_TYPE_MAGIC_COLOR,
    [2] = _G.DEBUFF_TYPE_CURSE_COLOR,
    [3] = _G.DEBUFF_TYPE_DISEASE_COLOR,
    [4] = _G.DEBUFF_TYPE_POISON_COLOR,
    [5] = _G.DEBUFF_TYPE_BLEED_COLOR,
    [0] = _G.DEBUFF_TYPE_NONE_COLOR,
}

local function _GetUFDispelTypeFallbackColor(dispelName, g)
    if issecretvalue and issecretvalue(dispelName) then return nil end
    if dispelName == "DISPELLABLE" then return nil end
    if type(dispelName) ~= "string" then return nil end

    local r = g and g["dispelType" .. dispelName .. "R"]
    if type(r) == "number" then
        return r, g["dispelType" .. dispelName .. "G"], g["dispelType" .. dispelName .. "B"]
    end

    local idx = _UF_DISPEL_INDEX_BY_NAME[dispelName] or 0
    local obj = _UF_DEBUFF_COLOR_BY_INDEX[idx]
    if obj then
        if obj.GetRGBA then
            local r2, g2, b2 = obj:GetRGBA()
            return r2, g2, b2
        elseif obj.GetRGB then
            local r2, g2, b2 = obj:GetRGB()
            return r2, g2, b2
        elseif obj.r then
            return obj.r, obj.g, obj.b
        end
    end
    return nil
end

-- UF dispel color resolve.
--
-- TYPE mode queries the shared GF dispel color curve
-- (ns.GF._sharedDispelColorCurve, built from DB per-type colors in
-- MSUF_GF_Auras.lua). The returned Color object exposes RGBA via
-- GetRGBA(); those values may be secret but C-side consumers
-- (SetBackdropBorderColor, LibCustomGlow → SetVertexColor) pass them
-- through safely — NO Lua arithmetic, NO CreateColor.
--
-- Prior Beta 5 bug: this function called a non-existent
-- `_G.MSUF_A2_GetDebuffColorCurve()` factory, so TYPE mode's curve was
-- always nil and colour resolution silently fell through to the single-
-- color default. Only TYPE colours in SINGLE mode worked — exactly the
-- "multi-color dispel broken" symptom users reported.
local function _GetUFDispelColor(dispelName, unit, auraID, cfg, preferTypeColor)
    local g = MSUF_DB and MSUF_DB.general
    local mode = (cfg and cfg.dispelColorMode) or (g and g.hlDispelColorMode) or "SINGLE"
    if mode ~= "TYPE" then
        if preferTypeColor then
            local tr, tg, tb = _GetUFDispelTypeFallbackColor(dispelName, g)
            if tr then return tr, tg, tb end
        end
        if cfg then
            return cfg.dispelR or 0.25, cfg.dispelG or 0.75, cfg.dispelB or 1.00
        end
        return _ReadColorValue(g, "hlDispelColorR", "dispelBorderColorR", 0.25),
               _ReadColorValue(g, "hlDispelColorG", "dispelBorderColorG", 0.75),
               _ReadColorValue(g, "hlDispelColorB", "dispelBorderColorB", 1.00)
    end

    -- Bleed/Enrage are classified from aura.dispelType, not normal dispelName.
    -- Some clients do not return a useful GetAuraDispelTypeColor result for
    -- them, so use the resolved type color directly like Danders does.
    if dispelName == "Bleed" then
        local br, bg, bb = _GetUFDispelTypeFallbackColor(dispelName, g)
        if br then return br, bg, bb end
    end

    local CUA = _G.C_UnitAuras
    local curve = ns and ns.GF and ns.GF._sharedDispelColorCurve
    if CUA and curve and unit and auraID and type(CUA.GetAuraDispelTypeColor) == "function" then
        local color = CUA.GetAuraDispelTypeColor(unit, auraID, curve)
        if color then
            -- GetRGBA is the only secret-safe accessor — GetRGB can return nil
            -- on secret-tainted Color objects. Returned values may still be
            -- secret; callers only pass them to C-side color sinks.
            if color.GetRGBA then
                local r, gg, b = color:GetRGBA()
                if r ~= nil then return r, gg, b end
            end
            if color.GetRGB then
                local r, gg, b = color:GetRGB()
                if r ~= nil then return r, gg, b end
            end
        end
    end

    -- Non-curve fallbacks: dispel name lookup from DB and Blizzard color globals.
    -- Midnight/Beta can return dispelName as a secret string; string comparisons
    -- on that value taint/error, so fall back to the generic dispel color.
    local fr, fg, fb = _GetUFDispelTypeFallbackColor(dispelName, g)
    if fr then return fr, fg, fb end

    if cfg then
        return cfg.dispelR or 0.25, cfg.dispelG or 0.75, cfg.dispelB or 1.00
    end
    return _ReadColorValue(g, "hlDispelColorR", "dispelBorderColorR", 0.25),
           _ReadColorValue(g, "hlDispelColorG", "dispelBorderColorG", 0.75),
           _ReadColorValue(g, "hlDispelColorB", "dispelBorderColorB", 1.00)
end

local _UF_PRIORITY_DISPEL_TYPE_BY_KEY = {
    magic = "Magic",
    curse = "Curse",
    disease = "Disease",
    poison = "Poison",
    bleed = "Bleed",
}
local _UF_PRIORITY_KEY_BY_DISPEL_TYPE = {
    Magic = "magic",
    Curse = "curse",
    Disease = "disease",
    Poison = "poison",
    Bleed = "bleed",
}
local _UF_PRIORITY_KEY_ALIAS = {
    Dispel = "dispel",
    DISPEL = "dispel",
    dispellable = "dispel",
    Magic = "magic",
    MAGIC = "magic",
    Curse = "curse",
    CURSE = "curse",
    Disease = "disease",
    DISEASE = "disease",
    Poison = "poison",
    POISON = "poison",
    Bleed = "bleed",
    BLEED = "bleed",
    Aggro = "aggro",
    AGGRO = "aggro",
    Purge = "purge",
    PURGE = "purge",
    BossTarget = "bossTarget",
    Boss_Target = "bossTarget",
    ["Boss Target"] = "bossTarget",
    ["boss target"] = "bossTarget",
    boss_target = "bossTarget",
    bosstarget = "bossTarget",
    BOSS_TARGET = "bossTarget",
}
local _UF_DISPEL_PRIORITY_TYPE_KEYS = { "magic", "curse", "disease", "poison", "bleed" }
local _UF_DISPEL_TYPE_MARKER_G = 0.37
local _UF_DISPEL_TYPE_MARKER_B = 0.73
local _UF_DISPEL_TYPE_MARKER_R = {
    Magic   = 0.11,
    Curse   = 0.22,
    Disease = 0.33,
    Poison  = 0.44,
    Bleed   = 0.55,
}
local _UF_DISPEL_TYPE_ID_CURVE
local function _UFNormalizePriorityKey(key)
    if type(key) ~= "string" then return nil end
    return _UF_PRIORITY_KEY_ALIAS[key] or key
end

local function _BuildUFDispelTypeIDCurve()
    local CUA = _G.C_UnitAuras
    local CCU = _G.C_CurveUtil
    local C = _G.CreateColor
    if not (CUA and type(CUA.GetAuraDispelTypeColor) == "function"
        and CCU and type(CCU.CreateColorCurve) == "function"
        and type(C) == "function") then
        return nil
    end
    local curve = CCU.CreateColorCurve()
    if curve.SetType then
        curve:SetType(_G.Enum and _G.Enum.LuaCurveType and _G.Enum.LuaCurveType.Step or 0)
    end
    if not curve.AddPoint then return curve end
    curve:AddPoint(0, C(0, 0, 0, 1))
    curve:AddPoint(1, C(_UF_DISPEL_TYPE_MARKER_R.Magic, _UF_DISPEL_TYPE_MARKER_G, _UF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(2, C(_UF_DISPEL_TYPE_MARKER_R.Curse, _UF_DISPEL_TYPE_MARKER_G, _UF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(3, C(_UF_DISPEL_TYPE_MARKER_R.Disease, _UF_DISPEL_TYPE_MARKER_G, _UF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(4, C(_UF_DISPEL_TYPE_MARKER_R.Poison, _UF_DISPEL_TYPE_MARKER_G, _UF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(5, C(_UF_DISPEL_TYPE_MARKER_R.Bleed, _UF_DISPEL_TYPE_MARKER_G, _UF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(9, C(_UF_DISPEL_TYPE_MARKER_R.Bleed, _UF_DISPEL_TYPE_MARKER_G, _UF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(11, C(_UF_DISPEL_TYPE_MARKER_R.Bleed, _UF_DISPEL_TYPE_MARKER_G, _UF_DISPEL_TYPE_MARKER_B, 1))
    return curve
end

local function _UFColorObjRGB(color)
    if not color then return nil end
    if color.GetRGBA then
        local r, g, b = color:GetRGBA()
        if r ~= nil then return r, g, b end
    end
    if color.GetRGB then
        local r, g, b = color:GetRGB()
        if r ~= nil then return r, g, b end
    end
    if color.r ~= nil then return color.r, color.g, color.b end
    return nil
end

local function _UFDispelTypeFromIDColor(r, g, b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    local abs = math and math.abs
    if abs and abs(g - _UF_DISPEL_TYPE_MARKER_G) <= 0.04 and abs(b - _UF_DISPEL_TYPE_MARKER_B) <= 0.04 then
        local bestType, bestDelta = nil, 0.04
        for dispelType, markerR in pairs(_UF_DISPEL_TYPE_MARKER_R) do
            local delta = abs(r - markerR)
            if delta <= bestDelta then
                bestType, bestDelta = dispelType, delta
            end
        end
        if bestType then return bestType end
    end

    -- Some builds return Blizzard-style colors here instead of evaluating the
    -- supplied curve. Keep this fallback separate so Bleed red cannot be read as Magic.
    if r > 0.75 and g < 0.25 and b > 0.75 then return "Bleed" end -- legacy marker
    if r > 0.65 and g < 0.28 and b < 0.28 then return "Bleed" end
    if b > 0.70 and g > 0.35 and r < 0.45 then return "Magic" end
    if b > 0.65 and r > 0.45 and g < 0.30 then return "Curse" end
    if g > 0.45 and r < 0.30 and b < 0.30 then return "Poison" end
    if r > 0.45 and g > 0.25 and g < 0.65 and b < 0.30 then return "Disease" end
    return nil
end

local function _ResolveUFAuraDispelType(unit, aura)
    if not aura then return nil end
    local dn = aura.dispelName
    if not (issecretvalue and issecretvalue(dn)) and _UF_PRIORITY_KEY_BY_DISPEL_TYPE[dn] then
        return dn
    end
    local dispelType = aura.dispelType
    if dispelType ~= nil and not (issecretvalue and issecretvalue(dispelType)) then
        dispelType = tonumber(dispelType) or dispelType
        if dispelType == 1 then return "Magic" end
        if dispelType == 2 then return "Curse" end
        if dispelType == 3 then return "Disease" end
        if dispelType == 4 then return "Poison" end
        if dispelType == 5 or dispelType == 9 or dispelType == 11 then return "Bleed" end
    end
    local aid = aura.auraInstanceID
    local CUA = _G.C_UnitAuras
    if not (unit and aid and CUA and type(CUA.GetAuraDispelTypeColor) == "function") then return nil end
    if not _UF_DISPEL_TYPE_ID_CURVE then
        _UF_DISPEL_TYPE_ID_CURVE = _BuildUFDispelTypeIDCurve()
    end
    if not _UF_DISPEL_TYPE_ID_CURVE then return nil end
    local color = CUA.GetAuraDispelTypeColor(unit, aid, _UF_DISPEL_TYPE_ID_CURVE)
    local r, g, b = _UFColorObjRGB(color)
    if issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then return nil end
    return _UFDispelTypeFromIDColor(r, g, b)
end

_G.MSUF_ResolveAuraDispelPriorityType = _ResolveUFAuraDispelType
local _UF_PRIORITY_SINGLE_DEFAULTS = { "dispel", "aggro", "purge", "bossTarget" }
local _UF_PRIORITY_TYPE_DEFAULTS = { "magic", "curse", "disease", "poison", "bleed", "aggro", "purge", "bossTarget" }
local _UF_PRIORITY_SINGLE_ALLOWED = { dispel = true, aggro = true, purge = true, bossTarget = true }
local _UF_PRIORITY_TYPE_ALLOWED = {
    magic = true,
    curse = true,
    disease = true,
    poison = true,
    bleed = true,
    dispel = true,
    aggro = true,
    purge = true,
    bossTarget = true,
}

local function _UFHighlightPriorityRawHasAllowedKey(prioOrder, allowed, key)
    if type(prioOrder) ~= "table" or not allowed[key] then return false end
    for i = 1, #prioOrder do
        if _UFNormalizePriorityKey(prioOrder[i]) == key then return true end
    end
    return false
end

local function _UFHighlightPriorityOrderHasTypeKey(prioOrder)
    if type(prioOrder) ~= "table" then return false end
    for i = 1, #prioOrder do
        local key = _UFNormalizePriorityKey(prioOrder[i])
        if key ~= "dispel" and _UF_PRIORITY_TYPE_ALLOWED[key] then return true end
    end
    return false
end

local _UF_DISPEL_TYPE_ORDER_KEYS = {
    magic = true,
    curse = true,
    disease = true,
    poison = true,
    bleed = true,
}

local function _UFHighlightPriorityOrderHasDispelTypeKey(prioOrder)
    if type(prioOrder) ~= "table" then return false end
    for i = 1, #prioOrder do
        if _UF_DISPEL_TYPE_ORDER_KEYS[_UFNormalizePriorityKey(prioOrder[i])] then return true end
    end
    return false
end

local function _UFOverlayUsesOwnPriority(cfg)
    return false
end

local function _UFOverlayPriorityState(cfg)
    if not cfg then return false, nil end
    return _BoolEnabled(cfg.highlightPrioEnabled), cfg.highlightPrioOrder
end

_G.MSUF_UFDispelTypePriorityState = function(cfg, useOverlayPriority)
    if not cfg then return false, nil end
    if useOverlayPriority then
        return _UFOverlayPriorityState(cfg)
    end
    if _BoolEnabled(cfg.highlightPrioEnabled) and _UFHighlightPriorityOrderHasDispelTypeKey(cfg.highlightPrioOrder) then
        return true, cfg.highlightPrioOrder
    end
    return false, nil
end

local function _UFDispelScanPriorityConfig(cfg, useOverlayPriority)
    if not cfg then return false, nil end
    local serial = cfg.serial or 0
    if useOverlayPriority then
        if cfg._msufOverlayDispelPrioSerial == serial then
            return cfg._msufOverlayDispelPrioEnabled == true, cfg._msufOverlayDispelPrioOrder
        end
    elseif cfg._msufBorderDispelPrioSerial == serial then
        return cfg._msufBorderDispelPrioEnabled == true, cfg._msufBorderDispelPrioOrder
    end
    local customEnabled, order = _G.MSUF_UFDispelTypePriorityState(cfg, useOverlayPriority)
    local typeColorMode = cfg.dispelColorMode == "TYPE"
    local customTypeOrder = customEnabled and _UFHighlightPriorityOrderHasDispelTypeKey(order)
    if not typeColorMode and not customTypeOrder then
        if useOverlayPriority then
            cfg._msufOverlayDispelPrioSerial = serial
            cfg._msufOverlayDispelPrioEnabled = false
            cfg._msufOverlayDispelPrioOrder = order
        else
            cfg._msufBorderDispelPrioSerial = serial
            cfg._msufBorderDispelPrioEnabled = false
            cfg._msufBorderDispelPrioOrder = order
        end
        return false, order
    end
    order = customEnabled and order or nil
    if useOverlayPriority then
        cfg._msufOverlayDispelPrioSerial = serial
        cfg._msufOverlayDispelPrioEnabled = true
        cfg._msufOverlayDispelPrioOrder = order
    else
        cfg._msufBorderDispelPrioSerial = serial
        cfg._msufBorderDispelPrioEnabled = true
        cfg._msufBorderDispelPrioOrder = order
    end
    return true, order
end

_UFDispelScanCustomTypePriorityEnabled = function(cfg, useOverlayPriority)
    if not cfg then return false end
    local serial = cfg.serial or 0
    if useOverlayPriority then
        if cfg._msufOverlayDispelCustomSerial == serial then
            return cfg._msufOverlayDispelCustomEnabled == true
        end
    elseif cfg._msufBorderDispelCustomSerial == serial then
        return cfg._msufBorderDispelCustomEnabled == true
    end
    local enabled, order = _G.MSUF_UFDispelTypePriorityState(cfg, useOverlayPriority)
    local customEnabled = enabled and _UFHighlightPriorityOrderHasDispelTypeKey(order) or false
    if useOverlayPriority then
        cfg._msufOverlayDispelCustomSerial = serial
        cfg._msufOverlayDispelCustomEnabled = customEnabled
    else
        cfg._msufBorderDispelCustomSerial = serial
        cfg._msufBorderDispelCustomEnabled = customEnabled
    end
    return customEnabled
end

local function _UFDispelScanPriorityEnabled(cfg, useOverlayPriority)
    local enabled = _UFDispelScanPriorityConfig(cfg, useOverlayPriority)
    return enabled == true
end

local function _UFDispelScanResolveType(cfg, useOverlayPriority, triggerMode)
    triggerMode = _NormalizeDispelBorderTrigger(triggerMode)
    return _UFDispelScanPriorityEnabled(cfg, useOverlayPriority)
        or triggerMode == DISPEL_TRIGGER_TYPE
        or (cfg and cfg.dispelColorMode == "TYPE")
end

local function _UFDispelTypePriorityRank(cfg, useOverlayPriority, dispelType, forceDefaultOrder)
    local enabled, prioOrder = _UFDispelScanPriorityConfig(cfg, useOverlayPriority)
    if not enabled then
        if not forceDefaultOrder then return nil end
        prioOrder = nil
    end
    if issecretvalue and issecretvalue(dispelType) then return 999 end
    -- dispelType may arrive as a capitalised dispelName ("Bleed") or as a
    -- lowercase priority key ("bleed") from _ResolveUFAuraDispelType.
    -- _UF_PRIORITY_KEY_BY_DISPEL_TYPE maps capitalised → lowercase, so a
    -- lowercase input will miss. Fall back to checking PRIORITY_TYPE_ALLOWED
    -- directly, which uses the same lowercase keys as the priority order.
    local allowed = _UF_DISPEL_TYPE_ORDER_KEYS
    local defaults = _UF_DISPEL_PRIORITY_TYPE_KEYS
    local wanted = _UF_PRIORITY_KEY_BY_DISPEL_TYPE[dispelType]
        or (allowed[dispelType] and dispelType)
    if not wanted then return 999 end

    local rank = 1
    if type(prioOrder) == "table" then
        for _, kind in ipairs(prioOrder) do
            kind = _UFNormalizePriorityKey(kind)
            if allowed[kind] then
                if kind == wanted then return rank end
                rank = rank + 1
            end
        end
    end
    for i = 1, #defaults do
        local kind = defaults[i]
        if not _UFHighlightPriorityRawHasAllowedKey(prioOrder, allowed, kind) then
            if kind == wanted then return rank end
            rank = rank + 1
        end
    end
    return 999
end

local _UF_PRIORITY_SIGNATURE = {
    magic = 1,
    curse = 2,
    disease = 3,
    poison = 4,
    bleed = 5,
    dispel = 6,
    aggro = 7,
    purge = 8,
    bossTarget = 9,
}

local function _UFDispelScanPrioritySignature(cfg, useOverlayPriority)
    if cfg then
        local serial = cfg.serial or 0
        if useOverlayPriority then
            if cfg._msufOverlayDispelPrioSigSerial == serial and cfg._msufOverlayDispelPrioSig ~= nil then
                return cfg._msufOverlayDispelPrioSig
            end
        elseif cfg._msufBorderDispelPrioSigSerial == serial and cfg._msufBorderDispelPrioSig ~= nil then
            return cfg._msufBorderDispelPrioSig
        end
    end
    local enabled, order = _UFDispelScanPriorityConfig(cfg, useOverlayPriority)
    local sig = enabled and 1 or 0
    if useOverlayPriority and _UFOverlayUsesOwnPriority(cfg) then
        sig = sig + 10
    end
    if cfg and cfg.dispelColorMode == "TYPE" then
        sig = sig + 20
    end
    if type(order) == "table" then
        for i = 1, #order do
            sig = sig * 11 + (_UF_PRIORITY_SIGNATURE[_UFNormalizePriorityKey(order[i])] or 0)
        end
    end
    if cfg then
        local serial = cfg.serial or 0
        if useOverlayPriority then
            cfg._msufOverlayDispelPrioSigSerial = serial
            cfg._msufOverlayDispelPrioSig = sig
        else
            cfg._msufBorderDispelPrioSigSerial = serial
            cfg._msufBorderDispelPrioSig = sig
        end
    end
    return sig
end

local function _ResolveUFHighlightPriorityColor(hlKey, cfg, dispelType, unit, auraID)
    if hlKey == 1 then
        return cfg.aggroR or 1.00, cfg.aggroG or 0.50, cfg.aggroB or 0.00
    elseif hlKey == 2 then
        return _GetUFDispelColor(dispelType, unit, auraID, cfg)
    elseif hlKey == 3 then
        return cfg.purgeR or 1.00, cfg.purgeG or 0.85, cfg.purgeB or 0.00
    elseif hlKey == 4 then
        return cfg.bossTargetR or 1.00, cfg.bossTargetG or 0.82, cfg.bossTargetB or 0.00
    end
    return 0, 0, 0
end

local _UF_HIGHLIGHT_KIND_BY_KEY = {
    [1] = "aggro",
    [2] = "dispel",
    [3] = "purge",
    [4] = "bossTarget",
}

local function _UFHighlightOrderKeyMatches(kind, orderKey, dispelType)
    if kind == "dispel" then
        return orderKey == "dispel" or _UF_DISPEL_TYPE_ORDER_KEYS[orderKey] == true
    end
    return orderKey == kind
end

local function _UFHighlightLayerOffset(cfg, hlKey, dispelType)
    local kind = _UF_HIGHLIGHT_KIND_BY_KEY[hlKey]
    if not kind then return UF_LAYER_HIGHLIGHT end

    local order = cfg and cfg.highlightPrioOrder
    local enabled = cfg and _BoolEnabled(cfg.highlightPrioEnabled)
    local typeMode = (cfg and cfg.dispelColorMode == "TYPE")
        or (enabled and _UFHighlightPriorityOrderHasTypeKey(order))
    local allowed = typeMode and _UF_PRIORITY_TYPE_ALLOWED or _UF_PRIORITY_SINGLE_ALLOWED
    local defaults = typeMode and _UF_PRIORITY_TYPE_DEFAULTS or _UF_PRIORITY_SINGLE_DEFAULTS
    local pos, count = nil, 0

    local function consider(orderKey)
        orderKey = _UFNormalizePriorityKey(orderKey)
        if not allowed[orderKey] then return end
        count = count + 1
        if not pos and _UFHighlightOrderKeyMatches(kind, orderKey, dispelType) then
            pos = count
        end
    end

    if enabled and type(order) == "table" then
        for i = 1, #order do
            consider(order[i])
        end
    end
    for i = 1, #defaults do
        local orderKey = defaults[i]
        if not (enabled and _UFHighlightPriorityRawHasAllowedKey(order, allowed, orderKey)) then
            consider(orderKey)
        end
    end

    if not pos and kind == "dispel" then pos = 1 end
    if not pos then pos = count end
    if count < 1 then count, pos = 1, 1 end
    return UF_LAYER_HIGHLIGHT + (count - pos)
end

local _UF_HIGHLIGHT_FRAME_KEY_BY_LOGICAL = {
    [1] = "aggro",
    [2] = "dispel",
    [3] = "purge",
    [4] = "bossTarget",
}

local function _UFDispelPriorityKey(dispelType)
    if issecretvalue and issecretvalue(dispelType) then return nil end
    return _UF_PRIORITY_KEY_BY_DISPEL_TYPE[dispelType]
        or (_UF_DISPEL_TYPE_ORDER_KEYS[dispelType] and dispelType)
end

local function _UFHighlightUsesTypeLane(cfg)
    if not cfg then return false end
    return cfg.dispelColorMode == "TYPE"
        or (_BoolEnabled(cfg.highlightPrioEnabled) and _UFHighlightPriorityOrderHasTypeKey(cfg.highlightPrioOrder))
end

local function _UFHighlightFrameKey(cfg, hlKey, dispelType)
    return _UF_HIGHLIGHT_FRAME_KEY_BY_LOGICAL[hlKey] or hlKey
end

local function _UFDispelOverlayUsesTypeLane(cfg)
    return false
end

local function _UFDispelOverlayFrameKey(cfg, dispelType)
    return "default"
end

------------------------------------------------------------------------
-- UnitFrame dispel overlay (health-bar tint, event-driven via the existing
-- dispel aura driver). Overlay and border keep separate detected states so
-- users can e.g. show the border only for "dispellable by me" while tinting
-- the player frame for "any debuff".
------------------------------------------------------------------------
local _UF_DISPEL_OVERLAY_TEXTURE_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\"
local _UF_DISPEL_OVERLAY_TEXTURES = {
    FULL   = MSUF_TEX_WHITE8,
    TOP    = _UF_DISPEL_OVERLAY_TEXTURE_ROOT .. "MSUF_Grad_V",
    BOTTOM = _UF_DISPEL_OVERLAY_TEXTURE_ROOT .. "MSUF_Grad_V_Rev",
    LEFT   = _UF_DISPEL_OVERLAY_TEXTURE_ROOT .. "MSUF_Grad_H",
    RIGHT  = _UF_DISPEL_OVERLAY_TEXTURE_ROOT .. "MSUF_Grad_H_Rev",
}

local function _UFDispelTestApplies(frame)
    if not (frame and _G.MSUF_BorderTestModesActive == true and _G.MSUF_DispelBorderTestMode == true) then
        return false
    end
    local scope = _G.MSUF_DispelBorderTestScope or "shared"
    if scope == "shared" then return true end
    if scope == "party" or scope == "raid" or scope == "mythicraid"
        or scope == "gf_party" or scope == "gf_raid" or scope == "gf_mythicraid" then
        return false
    end
    local unit = frame.unit
    if scope == "boss" then
        return type(unit) == "string" and unit:sub(1, 4) == "boss"
    end
    return unit == scope
end

local function _UFTestScopeApplies(frame, scope)
    if not frame then return false end
    scope = scope or "shared"
    if scope == "shared" then return true end
    if scope == "party" or scope == "raid" or scope == "mythicraid"
        or scope == "gf_party" or scope == "gf_raid" or scope == "gf_mythicraid" then
        return false
    end
    local unit = frame.unit
    if scope == "boss" then
        return type(unit) == "string" and unit:sub(1, 4) == "boss"
    end
    return unit == scope
end

local function _UFAggroTestApplies(frame)
    return frame and MSUF_IsAggroOutlineUnit(frame.unit)
        and _G.MSUF_BorderTestModesActive == true
        and _G.MSUF_AggroBorderTestMode == true
        and _UFTestScopeApplies(frame, _G.MSUF_AggroBorderTestScope or "shared")
end

local function _UFPurgeTestApplies(frame)
    if not frame then return false end
    local unit = frame.unit
    if unit ~= "target" and unit ~= "focus" and unit ~= "targettarget" then return false end
    return _G.MSUF_BorderTestModesActive == true
        and _G.MSUF_PurgeBorderTestMode == true
        and _UFTestScopeApplies(frame, _G.MSUF_PurgeBorderTestScope or "shared")
end

local function _UFBossTargetTestApplies(frame)
    if not (frame and _G.MSUF_BorderTestModesActive == true and _G.MSUF_BossTargetBorderTestMode == true) then
        return false
    end
    local unit = frame.unit
    if type(unit) ~= "string" or unit:sub(1, 4) ~= "boss" then return false end
    local idx = tonumber(unit:sub(5))
    return idx ~= nil and idx >= 1 and idx <= 5
end

local function _UFDispelOverlayBottomBar(frame)
    if not frame then return nil end
    local hpBar = frame.hpBar
    local power = frame.targetPowerBar or frame.powerBar
    if power and not frame._msufPowerBarDetached and (frame._msufPowerBarReserved or (power.IsShown and power:IsShown())) then
        return power
    end
    return hpBar
end

local function _EnsureUFDispelOverlay(frame, frameKey)
    if not (frame and frame.hpBar and F.CreateFrame) then return nil end
    frameKey = frameKey or "default"
    local overlays = frame._msufUFDispelOverlays
    if not overlays then
        overlays = {}
        frame._msufUFDispelOverlays = overlays
        if frame._msufUFDispelOverlay then
            overlays.default = frame._msufUFDispelOverlay
            frame._msufUFDispelOverlay._msufUFDOFrameKey = "default"
        end
    end
    local overlay = overlays[frameKey]
    if overlay then return overlay end

    overlay = F.CreateFrame("StatusBar", nil, frame)
    overlay:EnableMouse(false)
    overlay:SetStatusBarTexture(MSUF_TEX_WHITE8)
    overlay:SetMinMaxValues(0, 1)
    overlay:SetValue(1)
    overlay:SetStatusBarColor(1, 1, 1, 1)
    overlay:SetAlpha(0.35)
    _SyncUFFrameLayerAbove(overlay, frame.hpBar, UF_LAYER_DISPEL_OVERLAY)
    overlay._msufUFDOFrameKey = frameKey
    overlay:Hide()
    overlays[frameKey] = overlay
    if not frame._msufUFDispelOverlay then
        frame._msufUFDispelOverlay = overlay
    end

    local rounded = _G.MSUF_RoundedUF_OnUnitDispelOverlayChanged
    if type(rounded) == "function" then rounded(frame) end
    return overlay
end

local function _HideUFDispelOverlay(frame)
    if not frame then return end
    local overlays = frame._msufUFDispelOverlays
    if overlays then
        for _, overlay in pairs(overlays) do
            if overlay and overlay.Hide then overlay:Hide() end
            if overlay then overlay._msufUFDOFullValue = nil end
        end
    else
        local overlay = frame._msufUFDispelOverlay
        if overlay and overlay.Hide then overlay:Hide() end
    end
    frame._msufUFDispelOverlayNeedsHPSync = nil
end

local function _LayoutUFDispelOverlay(frame, overlay, cfg)
    local hpBar = frame and frame.hpBar
    if not (hpBar and overlay) then return end

    local style = (cfg and cfg.unitDispelOverlayStyle) or "FULL"
    if not _UF_DISPEL_OVERLAY_TEXTURES[style] then style = "FULL" end
    local currentOnly = cfg and cfg.unitDispelOverlayOnHealth ~= false

    local anchorTop = hpBar
    local anchorBottom = hpBar
    if style == "FULL" and not currentOnly then
        anchorBottom = _UFDispelOverlayBottomBar(frame) or hpBar
    end

    if overlay._msufUFDOStyle ~= style then
        overlay:SetStatusBarTexture(_UF_DISPEL_OVERLAY_TEXTURES[style] or MSUF_TEX_WHITE8)
        overlay._msufUFDOStyle = style
        local rounded = _G.MSUF_RoundedUF_OnUnitDispelOverlayChanged
        if type(rounded) == "function" then rounded(frame) end
    end

    local bottomChanged = overlay._msufUFDOAnchorBottom ~= anchorBottom
        or overlay._msufUFDOAnchorTop ~= anchorTop
    if bottomChanged then
        overlay:ClearAllPoints()
        overlay:SetPoint("TOPLEFT", anchorTop, "TOPLEFT", 0, 0)
        overlay:SetPoint("TOPRIGHT", anchorTop, "TOPRIGHT", 0, 0)
        overlay:SetPoint("BOTTOMLEFT", anchorBottom, "BOTTOMLEFT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", anchorBottom, "BOTTOMRIGHT", 0, 0)
        overlay._msufUFDOAnchorTop = anchorTop
        overlay._msufUFDOAnchorBottom = anchorBottom
    end
end

local function _SyncUFDispelOverlayHealth(frame, hp)
    local overlay = frame and frame._msufUFDispelOverlay
    if not (overlay and frame._msufUFDispelOverlayNeedsHPSync) then return end
    local hpBar = frame.hpBar
    local minV, maxV
    if hpBar and hpBar.GetMinMaxValues then
        minV, maxV = hpBar:GetMinMaxValues()
    end
    if minV == nil then minV = 0 end
    if maxV == nil and frame.unit and UnitHealthMax then maxV = UnitHealthMax(frame.unit) end
    if maxV == nil then maxV = 1 end
    overlay:SetMinMaxValues(minV, maxV)
    if hp == nil and frame.unit and UnitHealth then hp = UnitHealth(frame.unit) end
    overlay:SetValue(hp or 0)
end
_G.MSUF_UFDispelOverlay_SyncHealthValue = _G.MSUF_UFDispelOverlay_SyncHealthValue or _SyncUFDispelOverlayHealth

local function _UFDispelOverlayLayerOffset(cfg, dispelType)
    return UF_LAYER_DISPEL_OVERLAY
end

local function _PrimeUFDispelOverlayFrames(frame, cfg)
    if not (frame and cfg and cfg.unitDispelOverlayEnabled == true) or _MSUF_TestModeCombatLocked() then return end
    _EnsureUFDispelOverlay(frame, "default")
end

local function _ApplyUFDispelOverlay(frame, cfg)
    if not (frame and frame.unit and frame.hpBar) then return end
    cfg = cfg or _RefreshBorderSettingsForFrame(frame)

    local active = cfg and cfg.unitDispelOverlayEnabled == true
    -- Dispel border test mode is border-only. Overlay has its own detected
    -- state/priority lane and must not inherit the border test type.
    local dispelOn = frame._msufUFDispelOverlayOn == true
    local dispelType = frame._msufUFDispelOverlayType
    local auraID = frame._msufUFDispelOverlayAuraID
    local overlayOn = active and dispelOn
    if active and not _MSUF_TestModeCombatLocked() then
        _PrimeUFDispelOverlayFrames(frame, cfg)
    end
    if active and not overlayOn and not frame._msufUFDispelOverlay and not _MSUF_TestModeCombatLocked() then
        _PrimeUFDispelOverlayFrames(frame, cfg)
        local prepared = frame._msufUFDispelOverlay
        if prepared then
            _LayoutUFDispelOverlay(frame, prepared, cfg)
        end
    end
    if not overlayOn then
        _HideUFDispelOverlay(frame)
        return
    end

    local frameKey = _UFDispelOverlayFrameKey(cfg, dispelType)
    local overlay = _EnsureUFDispelOverlay(frame, frameKey)
    if not overlay then return end
    local overlays = frame._msufUFDispelOverlays
    if overlays then
        for key, other in pairs(overlays) do
            if other and key ~= frameKey and other.Hide then other:Hide() end
        end
    end
    frame._msufUFDispelOverlay = overlay
    _LayoutUFDispelOverlay(frame, overlay, cfg)

    local currentOnly = cfg and cfg.unitDispelOverlayOnHealth ~= false
    if currentOnly then
        frame._msufUFDispelOverlayNeedsHPSync = true
        overlay._msufUFDOFullValue = nil
        _SyncUFDispelOverlayHealth(frame)
    else
        frame._msufUFDispelOverlayNeedsHPSync = nil
        if overlay._msufUFDOFullValue ~= true then
            overlay:SetMinMaxValues(0, 1)
            overlay:SetValue(1)
            overlay._msufUFDOFullValue = true
        end
    end

    if overlay.SetReverseFill and frame.hpBar.GetReverseFill then
        local reverse = frame.hpBar:GetReverseFill() and true or false
        if overlay._msufUFDOReverse ~= reverse then
            overlay:SetReverseFill(reverse)
            overlay._msufUFDOReverse = reverse
        end
    end

    local r, g, b = _GetUFDispelColor(dispelType, frame.unit, auraID, cfg, _UFDispelOverlayUsesTypeLane(cfg))
    local tex = overlay.GetStatusBarTexture and overlay:GetStatusBarTexture()
    local rr, gg, bb = r or 0.25, g or 0.75, b or 1.00
    local secretColor = issecretvalue and (issecretvalue(rr) or issecretvalue(gg) or issecretvalue(bb))
    if tex and tex.SetVertexColor then
        if secretColor
            or overlay._msufUFDOColorR ~= rr
            or overlay._msufUFDOColorG ~= gg
            or overlay._msufUFDOColorB ~= bb
        then
            tex:SetVertexColor(rr, gg, bb, 1)
            if not secretColor then
                overlay._msufUFDOColorR, overlay._msufUFDOColorG, overlay._msufUFDOColorB = rr, gg, bb
            else
                overlay._msufUFDOColorR, overlay._msufUFDOColorG, overlay._msufUFDOColorB = nil, nil, nil
            end
        end
    else
        if secretColor
            or overlay._msufUFDOColorR ~= rr
            or overlay._msufUFDOColorG ~= gg
            or overlay._msufUFDOColorB ~= bb
        then
            overlay:SetStatusBarColor(rr, gg, bb, 1)
            if not secretColor then
                overlay._msufUFDOColorR, overlay._msufUFDOColorG, overlay._msufUFDOColorB = rr, gg, bb
            else
                overlay._msufUFDOColorR, overlay._msufUFDOColorG, overlay._msufUFDOColorB = nil, nil, nil
            end
        end
    end

    local alpha = (cfg and cfg.unitDispelOverlayAlpha) or 0.35
    if overlay._msufUFDOAlpha ~= alpha then
        overlay:SetAlpha(alpha)
        overlay._msufUFDOAlpha = alpha
    end
    do
        local layerOffset = _UFDispelOverlayLayerOffset(cfg, dispelType)
        local level = _SyncUFFrameLayerAbove(overlay, frame.hpBar, layerOffset)
        if level then
            overlay._msufUFDOFrameLevel = level
        end
        overlay._msufUFDOLayerOffset = layerOffset
    end
    if not (overlay.IsShown and overlay:IsShown()) then overlay:Show() end
end

_G.MSUF_ApplyUnitDispelOverlay = _G.MSUF_ApplyUnitDispelOverlay or function(frame)
    _ApplyUFDispelOverlay(frame)
end

_G.MSUF_RefreshUnitDispelOverlays = _G.MSUF_RefreshUnitDispelOverlays or function()
    local frames = _G.MSUF_UnitFrames
    local seen = {}
    local function apply(frame)
        if frame and frame.unit and not seen[frame] then
            seen[frame] = true
            _ApplyUFDispelOverlay(frame)
        end
    end
    if type(frames) == "table" then
        for _, frame in pairs(frames) do
            apply(frame)
        end
    end
    apply(_G.MSUF_player)
    apply(_G.MSUF_target)
    apply(_G.MSUF_focus)
    apply(_G.MSUF_targettarget)
end

local _BAR_OUTLINE_LINE_KEYS = { "top", "bottom", "left", "right" }

local function _EnsureBarOutlineLine(o, owner, key)
    if not (o and owner and owner.CreateTexture) then return nil end

    local line = o[key]
    if not (line and line.ClearAllPoints and line.SetPoint and line.SetVertexColor) then
        line = owner:CreateTexture(nil, "OVERLAY")
        o[key] = line
    elseif line.GetParent and line.SetParent and line:GetParent() ~= owner then
        line:SetParent(owner)
    end

    if line.SetDrawLayer then line:SetDrawLayer("OVERLAY", 0) end
    if line.SetTexture then line:SetTexture(MSUF_TEX_WHITE8) end
    _MSUF_BorderDisableSnap(line)
    return line
end

local function _SetBarOutlineLineColor(o, r, g, b, a)
    if not o then return false end
    local colored = false
    for i = 1, #_BAR_OUTLINE_LINE_KEYS do
        local line = o[_BAR_OUTLINE_LINE_KEYS[i]]
        if line and line.SetVertexColor then
            line:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
            colored = true
        end
    end
    return colored
end

local function _ReadBarOutlineColor()
    local fn = _G.MSUF_GetBarOutlineColor
    if type(fn) == "function" then
        local ok, r, g, b = pcall(fn)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        return tonumber(gen.barOutlineColorR) or 0,
               tonumber(gen.barOutlineColorG) or 0,
               tonumber(gen.barOutlineColorB) or 0
    end
    return 0, 0, 0
end

local function _LayoutBarOutlineLines(o, owner, edge)
    if not (o and owner) then return end

    local top = _EnsureBarOutlineLine(o, owner, "top")
    local bottom = _EnsureBarOutlineLine(o, owner, "bottom")
    local left = _EnsureBarOutlineLine(o, owner, "left")
    local right = _EnsureBarOutlineLine(o, owner, "right")

    if top then
        top:ClearAllPoints()
        _MSUF_BorderSetPoint(top, "TOPLEFT", owner, "TOPLEFT", 0, 0)
        _MSUF_BorderSetPoint(top, "TOPRIGHT", owner, "TOPRIGHT", 0, 0)
        _MSUF_BorderSetHeight(top, edge)
        top:Show()
    end
    if bottom then
        bottom:ClearAllPoints()
        _MSUF_BorderSetPoint(bottom, "BOTTOMLEFT", owner, "BOTTOMLEFT", 0, 0)
        _MSUF_BorderSetPoint(bottom, "BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
        _MSUF_BorderSetHeight(bottom, edge)
        bottom:Show()
    end
    if left then
        left:ClearAllPoints()
        _MSUF_BorderSetPoint(left, "TOPLEFT", owner, "TOPLEFT", 0, 0)
        _MSUF_BorderSetPoint(left, "BOTTOMLEFT", owner, "BOTTOMLEFT", 0, 0)
        _MSUF_BorderSetWidth(left, edge)
        left:Show()
    end
    if right then
        right:ClearAllPoints()
        _MSUF_BorderSetPoint(right, "TOPRIGHT", owner, "TOPRIGHT", 0, 0)
        _MSUF_BorderSetPoint(right, "BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
        _MSUF_BorderSetWidth(right, edge)
        right:Show()
    end
end

local function _ApplyUFBarBorderTint(self, showTint, r, g, b)
    local o = self and self._msufBarOutline
    local f = o and o.frame
    if not f then return end
    local cr, cg, cb = _ReadBarOutlineColor()
    if showTint then
        cr, cg, cb = r or 0, g or 0, b or 0
    end
    if not _SetBarOutlineLineColor(o, cr, cg, cb, 1) and f.SetBackdropBorderColor then
        f:SetBackdropBorderColor(cr, cg, cb, 1)
    end
end

local function MSUF_ReadDetachedPowerBarBorder(self)
    local unitKey = self and (self.msufConfigKey or self.unit)
    local readEnabled = _G.MSUF_ReadUnitPowerBarBorderEnabled
    local readSize = _G.MSUF_ReadUnitPowerBarBorderThickness
    local barsDB = MSUF_DB and MSUF_DB.bars

    local thickness
    local powerBorderEnabled
    if type(readEnabled) == "function" then
        powerBorderEnabled = readEnabled(unitKey) == true
    else
        powerBorderEnabled = barsDB and (barsDB.powerBarBorderEnabled == true) or false
    end

    if powerBorderEnabled then
        if type(readSize) == "function" then
            thickness = readSize(unitKey)
        else
            thickness = barsDB and tonumber(barsDB.powerBarBorderThickness or barsDB.powerBarBorderSize) or 1
        end
    else
        local detachedOverride = barsDB and barsDB.detachedPowerBarOutline
        if detachedOverride ~= nil then
            local override = tonumber(detachedOverride)
            if override ~= nil then thickness = override end
        end
    end

    if thickness == nil and type(MSUF_GetDesiredBarBorderThicknessAndStamp) == "function" then
        thickness = select(1, MSUF_GetDesiredBarBorderThicknessAndStamp(self))
    end

    thickness = tonumber(thickness) or 1
    if thickness < 0 then thickness = 0 elseif thickness > 6 then thickness = 6 end
    return thickness > 0, thickness
end

local function MSUF_HideDetachedPowerBarOutline(self)
    local outline = self and self._msufDetachedPBOutline
    if outline then
        outline:Hide()
    end
end
_G.MSUF_HideDetachedPowerBarOutline = MSUF_HideDetachedPowerBarOutline

local function MSUF_ApplyDetachedPowerBarOutline(self)
    local pb = self and self.targetPowerBar
    local outline = self and self._msufDetachedPBOutline
    if not (self and pb and self._msufPowerBarDetached and pb.IsShown and pb:IsShown()) then
        MSUF_HideDetachedPowerBarOutline(self)
        return
    end

    local enabled, thickness = MSUF_ReadDetachedPowerBarBorder(self)
    if not enabled or thickness <= 0 then
        MSUF_HideDetachedPowerBarOutline(self)
        return
    end

    if not outline then
        local template = (BackdropTemplateMixin and "BackdropTemplate") or nil
        outline = F.CreateFrame("Frame", nil, pb, template)
        outline:EnableMouse(false)
        self._msufDetachedPBOutline = outline
        outline._msufLastEdgeSize = -1
        outline._msufLastFrameLevel = -1
    end

    local frameLevel = (pb.GetFrameLevel and pb:GetFrameLevel() or 0) + 2
    if outline._msufLastFrameLevel ~= frameLevel and outline.SetFrameLevel then
        outline:SetFrameLevel(frameLevel)
        outline._msufLastFrameLevel = frameLevel
    end

    if outline.SetClipsChildren then outline:SetClipsChildren(false) end
    _MSUF_BorderDisableSnap(outline)
    if outline.SetBackdrop and outline._msufLineOutlineBackdropCleared ~= true then
        outline:SetBackdrop(nil)
        outline._msufLineOutlineBackdropCleared = true
    end

    local edge = _MSUF_BorderPixelSize(outline, thickness, 1)
    if edge <= 0 then edge = thickness end
    if outline._msufLastEdgeSize ~= edge then
        outline._msufLastEdgeSize = edge
        outline._msufDetachedPBStamp = nil
    end

    local stamp = tostring(edge) .. ":" .. tostring(frameLevel)
    if outline._msufDetachedPBStamp ~= stamp then
        outline:ClearAllPoints()
        _MSUF_BorderSetPoint(outline, "TOPLEFT", pb, "TOPLEFT", -edge, edge)
        _MSUF_BorderSetPoint(outline, "BOTTOMRIGHT", pb, "BOTTOMRIGHT", edge, -edge)
        outline._msufDetachedPBStamp = stamp
    end
    _LayoutBarOutlineLines(outline, outline, edge)
    local r, g, b = _ReadBarOutlineColor()
    _SetBarOutlineLineColor(outline, r, g, b, 1)
    outline:Show()
end
_G.MSUF_ApplyDetachedPowerBarOutline = MSUF_ApplyDetachedPowerBarOutline


-- Sub-function: apply the normal black bar outline.
local function MSUF_ApplyBarOutline(self, thickness, o)
    if thickness <= 0 then
        if o then
            ns.Util.HideKeys(o, ns.Bars._outlineParts, "frame")
        end
        self._msufBarOutlineThickness = 0
        self._msufBarOutlineEdgeSize = 0
        self._msufBarOutlineBottomIsPower = false
        MSUF_ApplyDetachedPowerBarOutline(self)
        return
    end
    if not o then
        o = {}
        self._msufBarOutline = o
    end
    ns.Util.HideKeys(o, ns.Bars._outlineParts)
    if not o.frame then
        local template = (BackdropTemplateMixin and "BackdropTemplate") or nil
        local f = F.CreateFrame("Frame", nil, self, template)
        f:EnableMouse(false)
        f:SetFrameStrata(self:GetFrameStrata())
        local baseLevel = self:GetFrameLevel() + 2
        if self.hpBar and self.hpBar.GetFrameLevel then
            baseLevel = self.hpBar:GetFrameLevel() + 2
        end
        f:SetFrameLevel(baseLevel)
        o.frame = f
        o._msufLastEdgeSize = -1
        o._msufLastFrameLevel = -1
    end
    local hb = self.hpBar
    local pb = self.targetPowerBar
    local pbDetached = self._msufPowerBarDetached
    local pbWanted = (pb ~= nil) and not pbDetached and (self._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
    local bottomBar = pbWanted and pb or hb
    local bottomIsPower = pbWanted and true or false
    local f = o.frame
    if not (hb and bottomBar and f) then
        if f and f.Hide then f:Hide() end
        MSUF_ApplyDetachedPowerBarOutline(self)
        return
    end

    if f.SetFrameStrata and self.GetFrameStrata then
        f:SetFrameStrata(self:GetFrameStrata())
    end
    local frameLevel = self:GetFrameLevel() + 2
    if hb.GetFrameLevel then
        frameLevel = hb:GetFrameLevel() + 2
    end
    if o._msufLastFrameLevel ~= frameLevel and f.SetFrameLevel then
        f:SetFrameLevel(frameLevel)
        o._msufLastFrameLevel = frameLevel
    end
    if f.SetClipsChildren then f:SetClipsChildren(false) end
    _MSUF_BorderDisableSnap(f)
    if f.SetBackdrop and o._msufLineOutlineBackdropCleared ~= true then
        f:SetBackdrop(nil)
        o._msufLineOutlineBackdropCleared = true
    end

    local edge = _MSUF_BorderPixelSize(f, thickness, 1)
    if edge <= 0 then edge = thickness end

    if o._msufLastEdgeSize ~= edge then
        o._msufLastEdgeSize = edge
        self._msufBarOutlineEdgeSize = -1
    end

    if (self._msufBarOutlineThickness ~= thickness) or (self._msufBarOutlineEdgeSize ~= edge) or (self._msufBarOutlineBottomIsPower ~= (bottomIsPower and true or false)) then
        f:ClearAllPoints()
        _MSUF_BorderSetPoint(f, "TOPLEFT", hb, "TOPLEFT", -edge, edge)
        _MSUF_BorderSetPoint(f, "BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", edge, -edge)
        self._msufBarOutlineThickness = thickness
        self._msufBarOutlineEdgeSize = edge
        self._msufBarOutlineBottomIsPower = bottomIsPower and true or false
    end
    _LayoutBarOutlineLines(o, f, edge)
    f:Show()
    if self._msufBarBorderTintActive then
        _SetBarOutlineLineColor(o, self._msufBarBorderTintR or 0, self._msufBarBorderTintG or 0, self._msufBarBorderTintB or 0, 1)
    else
        local r, g, b = _ReadBarOutlineColor()
        _SetBarOutlineLineColor(o, r, g, b, 1)
    end

    MSUF_ApplyDetachedPowerBarOutline(self)
end

MSUF_RefreshStaticUnitFrameOutlines = function(self)
    if not self or not self.unit then return end
    if self.border then
        self.border:Hide()
    end

    local thickness, stamp = 0, 0
    if type(MSUF_GetDesiredBarBorderThicknessAndStamp) == "function" then
        thickness, stamp = MSUF_GetDesiredBarBorderThicknessAndStamp(self)
    end
    thickness = tonumber(thickness) or 0
    self._msufBarBorderStamp = stamp

    MSUF_ApplyBarOutline(self, thickness, self._msufBarOutline)

    local pb = self.targetPowerBar or self.powerBar
    local applyPowerBorder = _G.MSUF_ApplyPowerBarBorder
    if pb and type(applyPowerBorder) == "function" then
        applyPowerBorder(pb)
    end

    if _G.MSUF_RoundedUF_Active == true then
        local fnR = _G.MSUF_RoundedUF_OnRareVisualsRefreshed
        if fnR then fnR(self) end
    end
end
_G.MSUF_RefreshStaticUnitFrameOutlines = MSUF_RefreshStaticUnitFrameOutlines

-- Sub-function: create/update highlight overlay frame for aggro/dispel/purge.
local function MSUF_EnsureHighlightOverlayFrame(self, frameKey, logicalKey)
    if not self then return nil end
    logicalKey = tonumber(logicalKey or frameKey) or 2
    if frameKey == nil or tonumber(frameKey) ~= nil then
        frameKey = _UF_HIGHLIGHT_FRAME_KEY_BY_LOGICAL[logicalKey] or logicalKey
    end
    local outlines = self._msufHighlightOutlines
    if not outlines then
        outlines = {}
        self._msufHighlightOutlines = outlines
    end

    local hlFrame = outlines[frameKey]
    if not hlFrame then
        local legacy = outlines[logicalKey]
        if legacy and (frameKey == _UF_HIGHLIGHT_FRAME_KEY_BY_LOGICAL[logicalKey]) then
            outlines[logicalKey] = nil
            outlines[frameKey] = legacy
            hlFrame = legacy
        end
    end
    if hlFrame then
        hlFrame._msufHighlightFrameKey = frameKey
        hlFrame._msufHighlightKey = logicalKey
        return hlFrame
    end
    if _MSUF_TestModeCombatLocked() then return nil end

    local template = (BackdropTemplateMixin and "BackdropTemplate") or nil
    hlFrame = F.CreateFrame("Frame", nil, self, template)
    hlFrame:EnableMouse(false)
    _SyncUFFrameLayerAbove(hlFrame, self.hpBar or self, UF_LAYER_HIGHLIGHT)
    hlFrame._msufHighlightFrameKey = frameKey
    hlFrame._msufHighlightKey = logicalKey
    hlFrame._msufHighlightEdgeSize = -1
    hlFrame._msufHighlightColorKey = -1
    hlFrame._msufHighlightBottomIsPower = nil
    outlines[frameKey] = hlFrame
    if logicalKey == 2 and not self._msufHighlightDispelOutline then
        self._msufHighlightDispelOutline = hlFrame
    end
    if not self._msufHighlightOutline then
        self._msufHighlightOutline = hlFrame
    end
    hlFrame:Hide()
    return hlFrame
end

local function MSUF_PrimeHighlightOverlayFrames(self, cfg)
    if not self or _MSUF_TestModeCombatLocked() then return end
    cfg = cfg or _RefreshBorderSettingsForFrame(self)

    local function prime(logicalKey, frameKey, dispelType)
        local frame = MSUF_EnsureHighlightOverlayFrame(self, frameKey, logicalKey)
        if not frame then return end
        local offset = _UFHighlightLayerOffset(cfg, logicalKey, dispelType)
        frame._msufHighlightLayerOffset = offset
        _SyncUFFrameLayerAbove(frame, self.hpBar or self, offset)
    end

    prime(1, "aggro")
    prime(2, "dispel")
    prime(3, "purge")
    prime(4, "bossTarget")
end

local function MSUF_HideHighlightOverlays(self)
    if not self then return end
    local outlines = self._msufHighlightOutlines
    if outlines then
        for _, frame in pairs(outlines) do
            if frame and frame.Hide then frame:Hide() end
        end
    elseif self._msufHighlightOutline and self._msufHighlightOutline.Hide then
        self._msufHighlightOutline:Hide()
    end
    self._msufHighlightColorKey = 0
    self._msufHighlightActiveKey = 0
    self._msufHighlightOutlineR, self._msufHighlightOutlineG, self._msufHighlightOutlineB = nil, nil, nil
    self._msufRoundedHighlightGlowAnchor = nil
end

local function MSUF_ApplyHighlightOverlay(self, hlKey, hlR, hlG, hlB, cfg, skipRounded, frameKey)
    local hlFrame = nil

    if hlKey == 0 then
        _StopDispelGlow(self)
        MSUF_HideHighlightOverlays(self)
        if _G.MSUF_RoundedUF_Active == true then
            local rounded = _G.MSUF_RoundedUF_OnUnitHighlightChanged
            if type(rounded) == "function" then rounded(self, 0, 0, 0, 0, cfg) end
        end
        return
    end

    local hlThickness = (cfg and cfg.highlightBorderThickness) or 2

    hlFrame = MSUF_EnsureHighlightOverlayFrame(self, frameKey or hlKey, hlKey)
    if not hlFrame then return end
    _SyncUFFrameLayerAbove(hlFrame, self.hpBar or self, hlFrame._msufHighlightLayerOffset or UF_LAYER_HIGHLIGHT)

    local hb = self.hpBar
    local pb = self.targetPowerBar
    local pbDetached = self._msufPowerBarDetached
    local pbWanted = (pb ~= nil) and not pbDetached and (self._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
    local bottomBar = pbWanted and pb or hb
    local bottomIsPower = pbWanted and true or false
    local snap = _G.MSUF_Snap
    local hlEdge = (type(snap) == "function") and snap(hlFrame, hlThickness) or hlThickness

    if hlFrame._msufHighlightEdgeSize ~= hlEdge then
        hlFrame:SetBackdrop({ edgeFile = MSUF_TEX_WHITE8, edgeSize = hlEdge })
        hlFrame._msufHighlightEdgeSize = hlEdge
        hlFrame._msufHighlightColorKey = -1
        hlFrame._msufHighlightBottomIsPower = nil
    end

    local colorChanged = (hlFrame._msufHighlightColorKey ~= hlKey)
    if not colorChanged then
        local secretColor = issecretvalue and (
            issecretvalue(hlR) or issecretvalue(hlG) or issecretvalue(hlB)
            or issecretvalue(hlFrame._msufHighlightOutlineR)
            or issecretvalue(hlFrame._msufHighlightOutlineG)
            or issecretvalue(hlFrame._msufHighlightOutlineB)
        )
        colorChanged = secretColor
            or hlFrame._msufHighlightOutlineR ~= hlR
            or hlFrame._msufHighlightOutlineG ~= hlG
            or hlFrame._msufHighlightOutlineB ~= hlB
    end
    if colorChanged then
        hlFrame:SetBackdropBorderColor(hlR, hlG, hlB, 1)
        hlFrame._msufHighlightColorKey = hlKey
    end
    hlFrame._msufHighlightOutlineR, hlFrame._msufHighlightOutlineG, hlFrame._msufHighlightOutlineB = hlR, hlG, hlB

    if hlFrame._msufHighlightBottomIsPower ~= bottomIsPower then
        hlFrame:ClearAllPoints()
        if hb then
            hlFrame:SetPoint("TOPLEFT", hb, "TOPLEFT", -hlEdge, hlEdge)
        end
        if bottomBar then
            hlFrame:SetPoint("BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", hlEdge, -hlEdge)
        end
        hlFrame._msufHighlightBottomIsPower = bottomIsPower
    end

    local roundedHandled = false
    if not skipRounded and _G.MSUF_RoundedUF_Active == true then
        local rounded = _G.MSUF_RoundedUF_OnUnitHighlightChanged
        if type(rounded) == "function" then
            roundedHandled = rounded(self, hlKey, hlR, hlG, hlB, cfg) and true or false
        end
    end

    if not skipRounded and hlKey == 2 and cfg.dispelGlowEnabled then
        _StartDispelGlow(self, hlR, hlG, hlB, cfg)
    elseif not skipRounded then
        _StopDispelGlow(self)
    end

    if roundedHandled then
        hlFrame:Hide()
    else
        self._msufRoundedHighlightGlowAnchor = nil
        hlFrame:Show()
    end
    return hlFrame
end

local function MSUF_ApplyHighlightLayers(self, cfg, layers)
    local active = {}
    local topKey, topR, topG, topB, topFrame, topOffset = 0, nil, nil, nil, nil, -1
    local dispelR, dispelG, dispelB
    local hasDispelLayer = false

    for i = 1, #layers do
        local layer = layers[i]
        local key = layer and layer.key
        if key then
            local frameKey = _UFHighlightFrameKey(cfg, key, layer.dispelType)
            local offset = _UFHighlightLayerOffset(cfg, key, layer.dispelType)
            local frame = MSUF_EnsureHighlightOverlayFrame(self, frameKey, key)
            if not frame and key == 2 and frameKey ~= "dispel" then
                frameKey = "dispel"
                frame = MSUF_EnsureHighlightOverlayFrame(self, frameKey, key)
            end
            if frame then
                frame._msufHighlightLayerOffset = offset
                active[frameKey] = true
                if key == 2 then
                    self._msufHighlightDispelOutline = frame
                    hasDispelLayer = true
                end
                MSUF_ApplyHighlightOverlay(self, key, layer.r, layer.g, layer.b, cfg, true, frameKey)
                if key == 2 then
                    dispelR, dispelG, dispelB = layer.r, layer.g, layer.b
                end
                if offset > topOffset then
                    topKey, topR, topG, topB, topFrame, topOffset = key, layer.r, layer.g, layer.b, frame, offset
                end
            end
        end
    end

    local outlines = self._msufHighlightOutlines
    if outlines then
        for key, frame in pairs(outlines) do
            if frame and not active[key] then frame:Hide() end
        end
    end

    if topKey == 0 then
        _StopDispelGlow(self)
        MSUF_HideHighlightOverlays(self)
        if _G.MSUF_RoundedUF_Active == true then
            local rounded = _G.MSUF_RoundedUF_OnUnitHighlightChanged
            if type(rounded) == "function" then rounded(self, 0, 0, 0, 0, cfg) end
        end
        return 0, nil, nil, nil
    end

    self._msufHighlightOutline = topFrame
    self._msufHighlightActiveKey = topKey
    self._msufHighlightColorKey = topKey
    self._msufHighlightOutlineR, self._msufHighlightOutlineG, self._msufHighlightOutlineB = topR, topG, topB

    local roundedHandled = false
    if _G.MSUF_RoundedUF_Active == true then
        local rounded = _G.MSUF_RoundedUF_OnUnitHighlightChanged
        if type(rounded) == "function" then
            roundedHandled = rounded(self, topKey, topR, topG, topB, cfg) and true or false
        end
    end
    if roundedHandled and outlines then
        for _, frame in pairs(outlines) do
            if frame then frame:Hide() end
        end
    elseif not roundedHandled then
        self._msufRoundedHighlightGlowAnchor = nil
    end

    if hasDispelLayer and cfg.dispelGlowEnabled then
        _StartDispelGlow(self, dispelR or topR, dispelG or topG, dispelB or topB, cfg)
    else
        _StopDispelGlow(self)
    end

    return topKey, topR, topG, topB
end

local function _UFWriteHighlightLayer(layers, index, key, r, g, b, dispelType)
    local layer = layers[index]
    if not layer then
        layer = {}
        layers[index] = layer
    end
    layer.key = key
    layer.r = r
    layer.g = g
    layer.b = b
    layer.dispelType = dispelType
    return index + 1
end

MSUF_ApplyRareVisuals = function(self)
    if not self or not self.unit then  return end
    local cfg = _RefreshBorderSettingsForFrame(self)
    MSUF_PrimeHighlightOverlayFrames(self, cfg)
    _PrimeUFDispelOverlayFrames(self, cfg)

    -- Aggro state detection.
    local aggroTest = _UFAggroTestApplies(self)
    local wantAggro = MSUF_IsAggroOutlineUnit(self.unit) and ((cfg.aggroOutlineMode == 1) or aggroTest)
    local threat = false
    if wantAggro then
        if aggroTest then
            threat = true
        else
            local raw = MSUF_GetAggroThreatSituation(self.unit)
            if raw ~= nil then
                local iss = _G.issecretvalue
                if iss and iss(raw) then
                    threat = (self._msufAggroOutlineOn == true)
                else
                    threat = (raw == 3)
                end
            end
        end
    end

    -- Dispel state detection.
    local dispel = false
    local dispelColorType = self._msufDispelType
    do
        local test = _UFDispelTestApplies(self)
        local wantDispel = (cfg.dispelOutlineMode == 1) or test
        if wantDispel then
            local u = self.unit
            if u == "player" or u == "target" or u == "focus" or u == "targettarget" then
                if test then
                    dispel = true
                    dispelColorType = _G.MSUF_DispelBorderTestType or "Magic"
                else
                    dispel = (self._msufDispelOutlineOn == true)
                end
            end
        end
    end

    -- Purge state detection.
    local purge = false
    do
        local test = _UFPurgeTestApplies(self)
        local wantPurge = (cfg.purgeOutlineMode == 1) or test
        if wantPurge then
            local u = self.unit
            if u == "target" or u == "focus" or u == "targettarget" then
                purge = test or (self._msufPurgeOutlineOn == true)
            end
        end
    end

    -- Boss target state detection.
    local bossTarget = false
    do
        local u = self.unit
        if type(u) == "string" and u:sub(1, 4) == "boss" then
            local idx = tonumber(u:sub(5))
            if idx and idx >= 1 and idx <= 5 then
                local test = _UFBossTargetTestApplies(self)
                local wantBossTarget = (cfg.bossTargetOutlineMode == 1) or test
                if wantBossTarget then
                    bossTarget = test or (self._msufBossTargetHLOn == true)
                end
            end
        end
    end

    local layers = self._msufHighlightLayerState
    if not layers then
        layers = {}
        self._msufHighlightLayerState = layers
    end
    local layerIndex = 1
    if threat then
        layerIndex = _UFWriteHighlightLayer(layers, layerIndex, 1,
            cfg.aggroR or 1.00, cfg.aggroG or 0.50, cfg.aggroB or 0.00)
    end
    if dispel then
        local r, g, b = _GetUFDispelColor(dispelColorType, self.unit, self._msufDispelAuraID, cfg, _UFHighlightUsesTypeLane(cfg))
        layerIndex = _UFWriteHighlightLayer(layers, layerIndex, 2, r, g, b, dispelColorType)
    end
    if purge then
        layerIndex = _UFWriteHighlightLayer(layers, layerIndex, 3,
            cfg.purgeR or 1.00, cfg.purgeG or 0.85, cfg.purgeB or 0.00)
    end
    if bossTarget then
        layerIndex = _UFWriteHighlightLayer(layers, layerIndex, 4,
            cfg.bossTargetR or 1.00, cfg.bossTargetG or 0.82, cfg.bossTargetB or 0.00)
    end
    for i = layerIndex, #layers do
        local layer = layers[i]
        if layer then layer.key = nil end
    end

    local hlKey, hlR, hlG, hlB = MSUF_ApplyHighlightLayers(self, cfg, layers)

    local tintBarBorder = (hlKey == 2)
    self._msufBarBorderTintActive = tintBarBorder and true or nil
    self._msufBarBorderTintR = tintBarBorder and hlR or nil
    self._msufBarBorderTintG = tintBarBorder and hlG or nil
    self._msufBarBorderTintB = tintBarBorder and hlB or nil
    _ApplyUFBarBorderTint(self, tintBarBorder, hlR, hlG, hlB)
    if cfg.unitDispelOverlayEnabled == true then
        _ApplyUFDispelOverlay(self, cfg)
    end
end
-- Export with RoundedUF notification (replaces former hooksecurefunc in RoundedUnitframes).
_G.MSUF_RefreshRareBarVisuals = function(frame)
    MSUF_ApplyRareVisuals(frame)
    if _G.MSUF_RoundedUF_Active == true then
        local fnR = _G.MSUF_RoundedUF_OnRareVisualsRefreshed; if fnR then fnR(frame) end
    end
end

local function _PrimeUnitHighlightFrames()
    if _MSUF_TestModeCombatLocked() then return end
    local iter = _G.MSUF_ForEachUnitFrame
    if type(iter) == "function" then
        iter(function(frame)
            if frame and frame.unit then
                MSUF_ApplyRareVisuals(frame)
            end
        end)
        return
    end
    local frames = _G.MSUF_UnitFrames
    if type(frames) == "table" then
        for _, frame in pairs(frames) do
            if frame and frame.unit then MSUF_ApplyRareVisuals(frame) end
        end
    end
end

do
    local prime = F.CreateFrame("Frame")
    prime:RegisterEvent("PLAYER_LOGIN")
    prime:SetScript("OnEvent", function(self)
        if self.UnregisterEvent then self:UnregisterEvent("PLAYER_LOGIN") end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, _PrimeUnitHighlightFrames)
        else
            _PrimeUnitHighlightFrames()
        end
    end)
end

-- Cold-path helpers for the Bars menu (no runtime cost during combat/raiding).
-- 1) Live-apply outline thickness while the Settings panel is open.
-- 2) Aggro border test mode so users can tune thickness visually.
_G.MSUF_ApplyBarOutlineThickness_All = _G.MSUF_ApplyBarOutlineThickness_All or function()
    -- IMPORTANT: Live updates must not depend on gradient toggles or queued UFCore flush.
    -- We do a direct apply (cold path) and also sync the UFCore border stamp so the
    -- next UFCore pass won't "snap back" to the previous cached thickness.
    if MSUF_BarBorderCache then
        MSUF_BarBorderCache.stamp = nil
        MSUF_BarBorderCache.thickness = 0
        if type(MSUF_BarBorderCache.byScope) == "table" then
            for k in pairs(MSUF_BarBorderCache.byScope) do
                MSUF_BarBorderCache.byScope[k] = nil
            end
        end
    end
    MSUF_ForEachUnitFrame(_Iter_SyncBorderStamps)
end

_G.MSUF_SetAggroBorderTestMode = _G.MSUF_SetAggroBorderTestMode or function(active, scope)
    active = _MSUF_EnableBorderTestMode(active)
    _G.MSUF_AggroBorderTestMode = active and true or false
    _G.MSUF_AggroBorderTestScope = scope or "shared"
    _MSUF_RefreshBorderTestModesActive()
    local testScope = _G.MSUF_AggroBorderTestScope
    local isShared = (testScope == "shared")
    local isGF = (testScope == "party" or testScope == "raid" or testScope == "mythicraid" or testScope == "gf_party" or testScope == "gf_raid" or testScope == "gf_mythicraid")

    local fn = _G.MSUF_RefreshRareBarVisuals
    local frames = _G.MSUF_UnitFrames
    if type(fn) == "function" then
        if isShared then
            local p = _ResolveUnitFrame("player"); if _FrameMatchesUnit(p, "player") then fn(p) end
            local t = _ResolveUnitFrame("target"); if _FrameMatchesUnit(t, "target") then fn(t) end
            local f = _ResolveUnitFrame("focus"); if _FrameMatchesUnit(f, "focus") then fn(f) end
            for i = 1, 5 do local u = "boss" .. i; local b = _ResolveUnitFrame(u); if _FrameMatchesUnit(b, u) then fn(b) end end
        elseif testScope == "boss" then
            for i = 1, 5 do local u = "boss" .. i; local b = _ResolveUnitFrame(u); if _FrameMatchesUnit(b, u) then fn(b) end end
        elseif not isGF then
            local uf = _ResolveUnitFrame(testScope); if _FrameMatchesUnit(uf, testScope) then fn(uf) end
        end
    end
    -- Also refresh Group Frames
    local GF = _G.MSUF_NS and _G.MSUF_NS.GF
    if GF and GF._UpdateAggro and GF.frames then
        for gf in pairs(GF.frames) do
            if not active then
                gf._msufGFAggroLevel = nil
            end
            GF._UpdateAggro(gf, gf.unit)
            if not active then
                local refresh = GF.RefreshBorder or _G.MSUF_GF_RefreshBorder
                if type(refresh) == "function" then refresh(gf, gf.unit) end
            end
        end
    end
end

-- Options-only: Test mode to force the dispel border on while the Settings panel is open.
-- This does NOT change the DB or aura filters; it only affects the outline highlight rendering.
-- scope: "shared" = all frames, "player"/"target"/etc = that UF only, "party"/"raid" = GF only
_G.MSUF_SetDispelBorderTestMode = _G.MSUF_SetDispelBorderTestMode or function(active, scope)
    active = _MSUF_EnableBorderTestMode(active)
    _G.MSUF_DispelBorderTestMode = active and true or false
    _G.MSUF_DispelBorderTestScope = scope or "shared"
    _MSUF_RefreshBorderTestModesActive()
    local testScope = _G.MSUF_DispelBorderTestScope
    local isShared = (testScope == "shared")
    local isGF = (testScope == "party" or testScope == "raid" or testScope == "mythicraid" or testScope == "gf_party" or testScope == "gf_raid" or testScope == "gf_mythicraid")

    -- UF frames: only refresh if shared or matching UF scope
    local fn = _G.MSUF_RefreshRareBarVisuals
    local frames = _G.MSUF_UnitFrames
    if type(fn) == "function" then
        local ufUnits = isShared and { "player", "target", "focus", "targettarget" } or (not isGF and { testScope } or {})
        for _, u in ipairs(ufUnits) do
            local uf = _ResolveUnitFrame(u)
            if _FrameMatchesUnit(uf, u) then
                fn(uf)
                _ApplyUFDispelOverlay(uf)
            end
        end
    end
    -- Also force-clear UF glow when turning off
    if not active then
        local seen = {}
        local function clearUF(uf)
            if not uf or seen[uf] then return end
            seen[uf] = true
            _StopDispelGlow(uf)
            _ApplyUFDispelOverlay(uf)
        end
        if type(frames) == "table" then
            for _, uf in pairs(frames) do clearUF(uf) end
        end
        clearUF(_G.MSUF_player)
        clearUF(_G.MSUF_target)
        clearUF(_G.MSUF_focus)
        clearUF(_G.MSUF_targettarget)
    end

    -- GF frames: only refresh if shared or matching GF scope
    local GF = _G.MSUF_NS and _G.MSUF_NS.GF
    if GF and GF._UpdateDispel and GF.frames then
        for gf in pairs(GF.frames) do
            local kind = gf._msufGFKind or "party"
            local matchScope = isShared or isGF
            -- When turning OFF: always clean up ALL GF frames
            if not active then
                gf._msufGFDispelType = nil
                local stopGFGlow = _G.MSUF_GF_StopDispelGlow
                if type(stopGFGlow) == "function" then
                    stopGFGlow(gf)
                else
                    local anchor = gf._msufGFDispelGlowAnchor
                    gf._msufGFDispelGlowActive = nil
                    gf._msufGFDispelGlowAnchor = nil
                    gf._msufGFDispelGlowStyle = nil
                    _StopDispelGlowOn(anchor)
                    local borders = gf._msufGFHighlightBorders
                    if borders then
                        for _, borderAnchor in pairs(borders) do
                            if borderAnchor and borderAnchor ~= anchor then _StopDispelGlowOn(borderAnchor) end
                        end
                    else
                        local borderAnchor = gf._msufGFHighlightBorder
                        if borderAnchor and borderAnchor ~= anchor then _StopDispelGlowOn(borderAnchor) end
                    end
                    if gf ~= anchor then _StopDispelGlowOn(gf) end
                end
                GF._UpdateDispel(gf, gf.unit)
                local refresh = GF.RefreshBorder or _G.MSUF_GF_RefreshBorder
                if type(refresh) == "function" then refresh(gf, gf.unit) end
                -- Overlay is decoupled from border; force-sync after test clears state
                local _applyDO = _G.MSUF_GF_ApplyDispelOverlay
                if type(_applyDO) == "function" then _applyDO(gf) end
            elseif matchScope then
                GF._UpdateDispel(gf, gf.unit)
            end
        end
    end
end

-- Options-only: Test mode to force the purge border on while the Settings panel is open.
_G.MSUF_SetPurgeBorderTestMode = _G.MSUF_SetPurgeBorderTestMode or function(active, scope)
    active = _MSUF_EnableBorderTestMode(active)
    _G.MSUF_PurgeBorderTestMode = active and true or false
    _G.MSUF_PurgeBorderTestScope = scope or "shared"
    _MSUF_RefreshBorderTestModesActive()
    local testScope = _G.MSUF_PurgeBorderTestScope
    local isShared = (testScope == "shared")
    local isGF = (testScope == "party" or testScope == "raid" or testScope == "mythicraid" or testScope == "gf_party" or testScope == "gf_raid" or testScope == "gf_mythicraid")
    local frames = _G.MSUF_UnitFrames
    if not frames then return end

    local fn = _G.MSUF_RefreshRareBarVisuals
    local units = { "target", "focus", "targettarget" }
    for _, u in ipairs(units) do
        local uf = frames[u]
        local scopeMatch = isShared or (not isGF and testScope == u)
        if uf and uf.unit == u and scopeMatch then
            if active then
                -- Show one sentinel at full alpha for test preview
                local pool = uf._msufPurgeSentinels
                if not pool then
                    pool = {}
                    uf._msufPurgeSentinels = pool
                end
                if #pool < 1 then
                    local template = (BackdropTemplateMixin and "BackdropTemplate") or nil
                    local s = CreateFrame("Frame", nil, uf, template)
                    s:EnableMouse(false)
                    _SyncUFFrameLayerAbove(s, uf.hpBar or uf, UF_LAYER_HIGHLIGHT)
                    s._msufEdge = -1
                    pool[1] = s
                end
                local s = pool[1]
                local cfg = _RefreshBorderSettingsForFrame(uf)
                local hlThickness = tonumber(cfg and cfg.highlightBorderThickness) or 2
                if hlThickness < 1 then hlThickness = 1 end
                local snap = _G.MSUF_Snap
                local edge = (type(snap) == "function") and snap(s, hlThickness) or hlThickness
                s:SetBackdrop({ edgeFile = MSUF_TEX_WHITE8, edgeSize = edge })
                local pr, pg, pb = (cfg and cfg.purgeR) or 1.00, (cfg and cfg.purgeG) or 0.85, (cfg and cfg.purgeB) or 0.00
                s:SetBackdropBorderColor(pr, pg, pb, 1)
                s:ClearAllPoints()
                local hb = uf.hpBar
                local pb2 = uf.targetPowerBar
                local pbWanted = (pb2 ~= nil) and (uf._msufPowerBarReserved or (pb2.IsShown and pb2:IsShown()))
                local bottomBar = pbWanted and pb2 or hb
                if hb then s:SetPoint("TOPLEFT", hb, "TOPLEFT", -edge, edge) end
                if bottomBar then s:SetPoint("BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", edge, -edge) end
                _SyncUFFrameLayerAbove(s, hb or uf, UF_LAYER_HIGHLIGHT)
                s._msufEdge = edge
                s:Show()
                s:SetAlpha(1)
                -- Hide excess
                for i = 2, #pool do pool[i]:SetAlpha(0) end
            else
                -- Hide all sentinels
                local pool = uf._msufPurgeSentinels
                if pool then
                    for i = 1, #pool do pool[i]:SetAlpha(0) end
                end
            end
            -- Refresh overlay so highlight priority system picks up the change.
            if type(fn) == "function" then fn(uf) end
        elseif uf and uf.unit == u then
            local pool = uf._msufPurgeSentinels
            if pool then
                for i = 1, #pool do pool[i]:SetAlpha(0) end
            end
            if type(fn) == "function" then fn(uf) end
        end
    end
end

-- Options-only: Test mode to force the boss-target border on while the Settings panel is open.
_G.MSUF_SetBossTargetBorderTestMode = _G.MSUF_SetBossTargetBorderTestMode or function(active)
    active = _MSUF_EnableBorderTestMode(active)
    _G.MSUF_BossTargetBorderTestMode = active and true or false
    _MSUF_RefreshBorderTestModesActive()
    local frames = _G.MSUF_UnitFrames
    local fn = _G.MSUF_RefreshRareBarVisuals
    if type(fn) ~= "function" or not frames then return end

    if not active and type(_G.MSUF_UpdateBossTargetHighlight) == "function" then
        _G.MSUF_UpdateBossTargetHighlight(true)
    end

    for i = 1, 5 do
        local uf = frames["boss" .. i]
        if uf and uf.unit == ("boss" .. i) then
            fn(uf)
        end
    end
end

-- Aggro outline event driver (event-only, no OnUpdate)
do
    local aggroPlayerEventsWanted = false

    local function AnyAggroOutlineEnabled()
        aggroPlayerEventsWanted = _OutlineModeEnabledForUnit("player", "aggroOutlineMode", "hlAggroEnabled")
        if aggroPlayerEventsWanted then return true end
        if _OutlineModeEnabledForUnit("target", "aggroOutlineMode", "hlAggroEnabled") then return true end
        if _OutlineModeEnabledForUnit("focus", "aggroOutlineMode", "hlAggroEnabled") then return true end
        for i = 1, 5 do
            if _OutlineModeEnabledForUnit("boss" .. i, "aggroOutlineMode", "hlAggroEnabled") then return true end
        end
        return false
    end

    local function RefreshAggroForUnit(u)
        if not u or not MSUF_IsAggroOutlineUnit(u) then return end
        local uf = _ResolveUnitFrame(u)
        if not _FrameMatchesUnit(uf, u) then return end
        local cfg = _RefreshBorderSettingsForFrame(uf)
        local aggroTestActive = _G.MSUF_BorderTestModesActive == true and _G.MSUF_AggroBorderTestMode == true
        if not (aggroTestActive or (cfg and cfg.aggroOutlineMode == 1)) then
            if uf._msufAggroOutlineOn then
                uf._msufAggroOutlineOn = nil
                local fn = _G.MSUF_RefreshRareBarVisuals
                if type(fn) == "function" then fn(uf) end
            end
            return
        end

        if not aggroTestActive then
            local on = false
            do
                local raw = MSUF_GetAggroThreatSituation(u)
                if raw ~= nil then
                    if issecretvalue and issecretvalue(raw) then return end
                    on = (raw == 3) and true or false
                end
            end
            if uf._msufAggroOutlineOn == on then return end
            uf._msufAggroOutlineOn = on
        end

        local fn = _G.MSUF_RefreshRareBarVisuals
        if type(fn) == "function" then fn(uf) end
    end

    local function RefreshAllAggroOutlineUnits()
        RefreshAggroForUnit("player")
        RefreshAggroForUnit("target")
        RefreshAggroForUnit("focus")
        for i = 1, 5 do
            RefreshAggroForUnit("boss" .. i)
        end
    end

    -- UNIT_THREAT_* stay on dedicated frame (EventBus rejects UNIT_* events)
    local ef = F.CreateFrame("Frame")
    ef:SetScript("OnEvent", function(_, event, unit)
        RefreshAggroForUnit(unit)
        if unit ~= "player" and aggroPlayerEventsWanted then
            RefreshAggroForUnit("player")
        end
    end)
    local function ApplyAggroOutlineEventRegistration()
        local want = AnyAggroOutlineEnabled()

        if want then
            if not ef:IsEventRegistered("UNIT_THREAT_SITUATION_UPDATE") then
                ef:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
            end
            if not ef:IsEventRegistered("UNIT_THREAT_LIST_UPDATE") then
                ef:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
            end
            do
                local _qTgt, _qFoc
                local function _flushTgt()
                    _qTgt = nil
                    RefreshAggroForUnit("target")
                    if aggroPlayerEventsWanted then RefreshAggroForUnit("player") end
                end
                local function _flushFoc() _qFoc = nil; RefreshAggroForUnit("focus") end
                MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_AGGRO_OUTLINE", function()
                    if not _qTgt then _qTgt = true; if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("BORDER_AGGRO_TARGET", _flushTgt) else C_Timer.After(0, _flushTgt) end end
                end)
                MSUF_EventBus_Register("PLAYER_FOCUS_CHANGED", "MSUF_AGGRO_OUTLINE", function()
                    if not _qFoc then _qFoc = true; if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("BORDER_AGGRO_FOCUS", _flushFoc) else C_Timer.After(0, _flushFoc) end end
                end)
            end
        else
            aggroPlayerEventsWanted = false
            if ef:IsEventRegistered("UNIT_THREAT_SITUATION_UPDATE") then
                ef:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
            end
            if ef:IsEventRegistered("UNIT_THREAT_LIST_UPDATE") then
                ef:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
            end
            if type(MSUF_EventBus_Unregister) == "function" then
                MSUF_EventBus_Unregister("PLAYER_TARGET_CHANGED", "MSUF_AGGRO_OUTLINE")
                MSUF_EventBus_Unregister("PLAYER_FOCUS_CHANGED", "MSUF_AGGRO_OUTLINE")
            end
        end
        RefreshAllAggroOutlineUnits()
    end

    _G.MSUF_AggroOutline_ApplyEventRegistration = ApplyAggroOutlineEventRegistration
    ApplyAggroOutlineEventRegistration()
end

-- Dispel / Purge border event driver: refresh the rare outline when dispellable debuffs
-- or purgeable buffs appear/disappear.
-- Dispel: HARMFUL|RAID_PLAYER_DISPELLABLE (O(1) filter, covers defensive cleanse).
-- Purge:  scans HELPFUL auras for isStealable (RAID_PLAYER_DISPELLABLE doesn't cover
--         Spellsteal / offensive purge in all patches).  Event-driven only, no OnUpdate.
-- Dispel (friendly debuffs) and Purge (enemy buffs) tracked independently.
do
    local f = F.CreateFrame("Frame")
    local _DISPEL_SCAN_FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"
    local _dispelScanSlots = {}
    local _dispelScanCache = {}

    local function ClearDispelScanCache(unit)
        if unit then
            _dispelScanCache[unit] = nil
            return
        end
        for k in pairs(_dispelScanCache) do
            _dispelScanCache[k] = nil
        end
    end

    local function ReadDispelAuraInfo(aura, unit, resolveType)
        if not aura then return false end

        local aid = aura.auraInstanceID
        local dispelType = resolveType and _ResolveUFAuraDispelType(unit, aura) or nil
        local dn = aura.dispelName
        local dnIsSecret = issecretvalue and issecretvalue(dn)
        if not dispelType and not dnIsSecret and type(dn) == "string" and dn ~= "" and dn ~= "None" and dn ~= "DISPELLABLE" then
            dispelType = dn
        end

        return true, aid, dispelType
    end

    local function ReadAnyDebuffAuraInfo(aura, requireDispelType, unit, resolveType)
        if not aura then return false end

        local aid = aura.auraInstanceID
        local dispelType = resolveType and _ResolveUFAuraDispelType(unit, aura) or nil
        local dn = aura.dispelName
        local dnIsSecret = issecretvalue and issecretvalue(dn)
        if dnIsSecret then
            if requireDispelType and not dispelType then return true, aid, nil end
        elseif not dispelType and type(dn) == "string" and dn ~= "" and dn ~= "None" and dn ~= "DISPELLABLE" then
            dispelType = dn
        elseif requireDispelType and not dispelType then
            return false
        end

        return true, aid, dispelType
    end

    local function ScanAuras2PlayerDebuffCache(unit, requireDispelType, cfg, useOverlayPriority, forceTypeRank)
        if unit ~= "player" then return false end
        local api = ns and ns.MSUF_Auras2
        local cache = api and api.Cache
        if type(cache) ~= "table" then return false end
        local all = type(cache.GetAll) == "function" and cache.GetAll(unit) or nil
        if all == nil and type(cache.FullScan) == "function" then
            pcall(cache.FullScan, unit)
            all = type(cache.GetAll) == "function" and cache.GetAll(unit) or nil
        end
        if type(all) ~= "table" then return false end
        local ranked = _UFDispelScanPriorityEnabled(cfg, useOverlayPriority) or forceTypeRank == true
        local resolveType = requireDispelType or ranked or _UFDispelScanResolveType(cfg, useOverlayPriority, DISPEL_TRIGGER_ANY)
        local bestHas, bestAid, bestType, bestRank = false, nil, nil, 1000
        for _, aura in pairs(all) do
            local harmful = aura and (aura._msufIsHelpful == false)
            if not harmful and aura then
                local isHarmful = aura.isHarmful
                if issecretvalue and issecretvalue(isHarmful) then
                    harmful = true
                else
                    harmful = isHarmful == true
                end
            end
            if harmful then
                local has, aid, dispelType = ReadAnyDebuffAuraInfo(aura, requireDispelType, unit, resolveType)
                if has then
                    if not ranked then return has, aid, dispelType end
                    local rank = _UFDispelTypePriorityRank(cfg, useOverlayPriority, dispelType, forceTypeRank == true)
                    if rank < bestRank then
                        bestHas, bestAid, bestType, bestRank = true, aid, dispelType, rank
                        if rank <= 1 then return true, bestAid, bestType end
                    end
                end
            end
        end
        if bestHas then return true, bestAid, bestType end
        return false
    end

    local function ScanHarmfulDebuff(unit, requireDispelType, cfg, useOverlayPriority, forceTypeRank)
        local ranked = _UFDispelScanPriorityEnabled(cfg, useOverlayPriority) or forceTypeRank == true
        local resolveType = requireDispelType or ranked or _UFDispelScanResolveType(cfg, useOverlayPriority, DISPEL_TRIGGER_ANY)
        local bestHas, bestAid, bestType, bestRank = false, nil, nil, 1000
        local CUA = C_UnitAuras
        local getSlots = CUA and CUA.GetAuraSlots
        local getBySlot = CUA and CUA.GetAuraDataBySlot
        if type(getSlots) == "function" and type(getBySlot) == "function" then
            local cont = nil
            repeat
                _dispelScanSlots[1], _dispelScanSlots[2], _dispelScanSlots[3], _dispelScanSlots[4], _dispelScanSlots[5],
                _dispelScanSlots[6], _dispelScanSlots[7], _dispelScanSlots[8], _dispelScanSlots[9], _dispelScanSlots[10],
                _dispelScanSlots[11], _dispelScanSlots[12], _dispelScanSlots[13], _dispelScanSlots[14], _dispelScanSlots[15],
                _dispelScanSlots[16], _dispelScanSlots[17], _dispelScanSlots[18], _dispelScanSlots[19], _dispelScanSlots[20],
                _dispelScanSlots[21], _dispelScanSlots[22], _dispelScanSlots[23], _dispelScanSlots[24], _dispelScanSlots[25],
                _dispelScanSlots[26], _dispelScanSlots[27], _dispelScanSlots[28], _dispelScanSlots[29], _dispelScanSlots[30],
                _dispelScanSlots[31], _dispelScanSlots[32], _dispelScanSlots[33], _dispelScanSlots[34], _dispelScanSlots[35],
                _dispelScanSlots[36], _dispelScanSlots[37], _dispelScanSlots[38], _dispelScanSlots[39], _dispelScanSlots[40],
                _dispelScanSlots[41] = getSlots(unit, "HARMFUL", 40, cont)
                cont = _dispelScanSlots[1]
                for i = 2, 41 do
                    local slot = _dispelScanSlots[i]
                    if not slot then break end
                    local has, aid, dispelType = ReadAnyDebuffAuraInfo(getBySlot(unit, slot), requireDispelType, unit, resolveType)
                    if has then
                        if not ranked then return has, aid, dispelType end
                        local rank = _UFDispelTypePriorityRank(cfg, useOverlayPriority, dispelType, forceTypeRank == true)
                        if rank < bestRank then
                            bestHas, bestAid, bestType, bestRank = true, aid, dispelType, rank
                            if rank <= 1 then return true, bestAid, bestType end
                        end
                    end
                end
            until not cont
            if bestHas then return true, bestAid, bestType end
            return ScanAuras2PlayerDebuffCache(unit, requireDispelType, cfg, useOverlayPriority, forceTypeRank)
        end

        local getByIndex = CUA and CUA.GetAuraDataByIndex
        if type(getByIndex) == "function" then
            local index = 1
            while true do
                local aura = getByIndex(unit, index, "HARMFUL")
                if not aura then break end
                local has, aid, dispelType = ReadAnyDebuffAuraInfo(aura, requireDispelType, unit, resolveType)
                if has then
                    if not ranked then return has, aid, dispelType end
                    local rank = _UFDispelTypePriorityRank(cfg, useOverlayPriority, dispelType, forceTypeRank == true)
                    if rank < bestRank then
                        bestHas, bestAid, bestType, bestRank = true, aid, dispelType, rank
                        if rank <= 1 then return true, bestAid, bestType end
                    end
                end
                index = index + 1
            end
            if bestHas then return true, bestAid, bestType end
            return ScanAuras2PlayerDebuffCache(unit, requireDispelType, cfg, useOverlayPriority, forceTypeRank)
        end

        if AuraUtil and AuraUtil.ForEachAura then
            local has, aid, dispelType = false, nil, nil
            AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(auraData)
                has, aid, dispelType = ReadAnyDebuffAuraInfo(auraData, requireDispelType, unit, resolveType)
                if not has then return false end
                if not ranked then return true end
                local rank = _UFDispelTypePriorityRank(cfg, useOverlayPriority, dispelType, forceTypeRank == true)
                if rank < bestRank then
                    bestHas, bestAid, bestType, bestRank = true, aid, dispelType, rank
                    if rank <= 1 then return true end
                end
                return false
            end, true)
            if ranked and bestHas then return true, bestAid, bestType end
            if has then return has, aid, dispelType end
        end

        return ScanAuras2PlayerDebuffCache(unit, requireDispelType, cfg, useOverlayPriority, forceTypeRank)
    end

    local function HasDispellableDebuffUncached(unit, triggerMode, cfg, useOverlayPriority)
        triggerMode = _NormalizeDispelBorderTrigger(triggerMode)
        if triggerMode == DISPEL_TRIGGER_ANY then
            return ScanHarmfulDebuff(unit, false, cfg, useOverlayPriority, true)
        elseif triggerMode == DISPEL_TRIGGER_TYPE then
            return ScanHarmfulDebuff(unit, true, cfg, useOverlayPriority, true)
        end

        local ranked = _UFDispelScanPriorityEnabled(cfg, useOverlayPriority)
        local resolveType = ranked or _UFDispelScanResolveType(cfg, useOverlayPriority, triggerMode)
        local bestHas, bestAid, bestType, bestRank = false, nil, nil, 1000
        local CUA = C_UnitAuras
        local getSlots = CUA and CUA.GetAuraSlots
        local getBySlot = CUA and CUA.GetAuraDataBySlot
        local getByIndex = CUA and CUA.GetAuraDataByIndex

        -- Legacy custom type priority can contain Magic/Curse/Disease/Poison/Bleed
        -- even while the dropdown still says "Dispellable by me". In that case,
        -- first resolve the best typed harmful debuff so a high-priority Bleed can
        -- sit above Aggro/Purge via frame level. If no typed debuff exists, fall
        -- back to the cheap player-dispellable scan below.
        if _UFDispelScanCustomTypePriorityEnabled(cfg, useOverlayPriority) then
            local has, aid, dispelType = ScanHarmfulDebuff(unit, true, cfg, useOverlayPriority, true)
            if has then return has, aid, dispelType end
        end

        if type(getByIndex) == "function" then
            local index = 1
            while true do
                local aura = getByIndex(unit, index, _DISPEL_SCAN_FILTER)
                if not aura then break end
                local has, aid, dispelType = ReadDispelAuraInfo(aura, unit, resolveType)
                if has then
                    if not ranked then return has, aid, dispelType end
                    local rank = _UFDispelTypePriorityRank(cfg, useOverlayPriority, dispelType)
                    if rank < bestRank then
                        bestHas, bestAid, bestType, bestRank = true, aid, dispelType, rank
                        if rank <= 1 then return true, bestAid, bestType end
                    end
                end
                index = index + 1
            end
            if bestHas then return true, bestAid, bestType end
        end

        if type(getSlots) == "function" then
            local cont = nil
            repeat
                _dispelScanSlots[1], _dispelScanSlots[2], _dispelScanSlots[3], _dispelScanSlots[4], _dispelScanSlots[5],
                _dispelScanSlots[6], _dispelScanSlots[7], _dispelScanSlots[8], _dispelScanSlots[9], _dispelScanSlots[10],
                _dispelScanSlots[11], _dispelScanSlots[12], _dispelScanSlots[13], _dispelScanSlots[14], _dispelScanSlots[15],
                _dispelScanSlots[16], _dispelScanSlots[17], _dispelScanSlots[18], _dispelScanSlots[19], _dispelScanSlots[20],
                _dispelScanSlots[21] = getSlots(unit, _DISPEL_SCAN_FILTER, 20, cont)
                cont = _dispelScanSlots[1]
                for i = 2, 21 do
                    local slot = _dispelScanSlots[i]
                    if not slot then break end
                    if type(getBySlot) == "function" then
                        local has, aid, dispelType = ReadDispelAuraInfo(getBySlot(unit, slot), unit, resolveType)
                        if has then
                            if not ranked then return has, aid, dispelType end
                            local rank = _UFDispelTypePriorityRank(cfg, useOverlayPriority, dispelType)
                            if rank < bestRank then
                                bestHas, bestAid, bestType, bestRank = true, aid, dispelType, rank
                                if rank <= 1 then return true, bestAid, bestType end
                            end
                        end
                    else
                        return true
                    end
                end
            until not cont
            if bestHas then return true, bestAid, bestType end
        end

        if AuraUtil and AuraUtil.ForEachAura then
            local has, aid, dispelType = false, nil, nil
            AuraUtil.ForEachAura(unit, "HARMFUL|RAID", nil, function(auraData)
                if not auraData then return true end
                local found, foundAid, foundType = ReadDispelAuraInfo(auraData, unit, resolveType)
                if found then
                    has, aid, dispelType = true, foundAid, foundType
                    if not ranked then return true end
                    local rank = _UFDispelTypePriorityRank(cfg, useOverlayPriority, dispelType)
                    if rank < bestRank then
                        bestHas, bestAid, bestType, bestRank = true, aid, dispelType, rank
                        if rank <= 1 then return true end
                    end
                    return false
                end
                return false
            end, true)
            if ranked and bestHas then return true, bestAid, bestType end
            return has, aid, dispelType
        end

        return false
    end

    local function HasDispellableDebuff(unit, triggerMode, cfg, useOverlayPriority)
        triggerMode = _NormalizeDispelBorderTrigger(triggerMode)
        local guid = UnitGUID and UnitGUID(unit) or unit
        if issecretvalue and issecretvalue(guid) then
            guid = nil
        end
        local serial = (cfg and cfg.serial) or (_borderCfg and _borderCfg.serial) or 0
        local overlayPriority = useOverlayPriority == true
        local prioSig = _UFDispelScanPrioritySignature(cfg, overlayPriority)
        local cache = _dispelScanCache[unit]
        if cache and issecretvalue and issecretvalue(cache.guid) then
            cache.guid = nil
        end
        local cacheGuid = cache and cache.guid
        if cache
            and cacheGuid == guid
            and cache.serial == serial
        then
            if overlayPriority then
                if cache.oTriggerMode == triggerMode and cache.oPrioSig == prioSig then
                    return cache.oHas, cache.oAid, cache.oDispelType
                end
            elseif cache.bTriggerMode == triggerMode and cache.bPrioSig == prioSig then
                return cache.bHas, cache.bAid, cache.bDispelType
            end
        end

        local has, aid, dispelType = HasDispellableDebuffUncached(unit, triggerMode, cfg, useOverlayPriority)
        if not cache then
            cache = {}
            _dispelScanCache[unit] = cache
        end
        if cacheGuid ~= guid or cache.serial ~= serial then
            cache.bTriggerMode, cache.bHas, cache.bAid, cache.bDispelType = nil, nil, nil, nil
            cache.oTriggerMode, cache.oHas, cache.oAid, cache.oDispelType = nil, nil, nil, nil
            cache.bPrioSig, cache.oPrioSig = nil, nil
            cache.guid = guid
            cache.serial = serial
        end
        if overlayPriority then
            cache.oTriggerMode = triggerMode
            cache.oPrioSig = prioSig
            cache.oHas = has
            cache.oAid = aid
            cache.oDispelType = dispelType
        else
            cache.bTriggerMode = triggerMode
            cache.bPrioSig = prioSig
            cache.bHas = has
            cache.bAid = aid
            cache.bDispelType = dispelType
        end
        return has, aid, dispelType
    end

    -- Purge/Spellsteal detection (combat-safe for 12.0).
    -- Secret booleans can't be compared or branched on, but visual APIs (SetAlpha,
    -- SetBackdropBorderColor) accept secret values directly.  We use "sentinel frames"
    -- ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â one per HELPFUL aura slot, all positioned identically over the unit frame border.
    -- Each sentinel's alpha is set from isStealable via EvaluateColorFromBoolean.
    -- The returned color has SECRET RGBA ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â we pass color.a straight to SetAlpha()
    -- (a visual API) so we never compare the secret value.  If ANY sentinel has
    -- alpha=1, the purge border is visually rendered (frame compositing = OR logic).
    local _colorTrue  = CreateColor and CreateColor(1, 1, 1, 1)
    local _colorFalse = CreateColor and CreateColor(0, 0, 0, 0)
    local _evalBool   = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean
    local _getSlots   = C_UnitAuras and C_UnitAuras.GetAuraSlots
    local _getBySlot  = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
    local _bdTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
    local _bdTable    = { edgeFile = MSUF_TEX_WHITE8, edgeSize = 0 }

    -- Cached purge color ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â refreshed once per UpdatePurgeSentinels call.
    local _purgeR, _purgeG, _purgeB = 1.00, 0.85, 0.00
    local function _RefreshPurgeColor(cfg)
        if not cfg then cfg = _RefreshBorderSettingsCache() end
        _purgeR, _purgeG, _purgeB = cfg.purgeR or 1.00, cfg.purgeG or 0.85, cfg.purgeB or 0.00
    end

    local function _EnsureSentinel(uf, idx)
        local pool = uf._msufPurgeSentinels
        if not pool then
            pool = {}
            uf._msufPurgeSentinels = pool
        end
        local s = pool[idx]
        if s then return s end
        s = F.CreateFrame("Frame", nil, uf, _bdTemplate)
        s:EnableMouse(false)
        _SyncUFFrameLayerAbove(s, uf.hpBar or uf, UF_LAYER_HIGHLIGHT)
        s:SetAlpha(0)
        s._msufEdge = -1
        pool[idx] = s
        return s
    end

    local function _LayoutSentinel(s, uf, edge)
        local pbDetached = uf._msufPowerBarDetached and true or false
        if s._msufEdge == edge and s._msufDetach == pbDetached then return end
        _bdTable.edgeSize = edge
        s:SetBackdrop(_bdTable)
        s:SetBackdropBorderColor(_purgeR, _purgeG, _purgeB, 1)
        s:ClearAllPoints()
        local hb = uf.hpBar
        local pb = uf.targetPowerBar
        local pbWanted = (pb ~= nil) and not pbDetached and (uf._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
        local bottomBar = pbWanted and pb or hb
        if hb then s:SetPoint("TOPLEFT", hb, "TOPLEFT", -edge, edge) end
        if bottomBar then s:SetPoint("BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", edge, -edge) end
        _SyncUFFrameLayerAbove(s, hb or uf, UF_LAYER_HIGHLIGHT)
        s._msufEdge = edge
        s._msufDetach = pbDetached
        s:Show()
    end

    -- Single-pass: scan HELPFUL slots and set sentinel alphas inline.
    -- No intermediate allSlots table ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â process each batch directly.
    local _purgeScratch = {}
    local function UpdatePurgeSentinels(uf, unit, cfg)
        if type(_getSlots) ~= "function" or type(_getBySlot) ~= "function" then return false end

        cfg = cfg or _RefreshBorderSettingsForFrame(uf)
        _RefreshPurgeColor(cfg)

        local hlThickness = cfg.highlightBorderThickness or 2
        local snap = _G.MSUF_Snap

        local sentIdx = 0
        local purgeOn = false
        local cont = nil
        repeat
            local t = _purgeScratch
            t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10],
            t[11], t[12], t[13], t[14], t[15], t[16], t[17], t[18], t[19], t[20], t[21]
                = _getSlots(unit, "HELPFUL", 20, cont)
            cont = t[1]
            for i = 2, 21 do
                local slot = t[i]
                if not slot then break end
                sentIdx = sentIdx + 1
                local s = _EnsureSentinel(uf, sentIdx)
                local edge = (type(snap) == "function") and snap(s, hlThickness) or hlThickness
                _LayoutSentinel(s, uf, edge)
                local data = _getBySlot(unit, slot)
                if data then
                    local stealable = data.isStealable
                    if not (issecretvalue and issecretvalue(stealable)) and stealable == true then
                        purgeOn = true
                    end
                    if _evalBool and _colorTrue then
                        local color = _evalBool(stealable, _colorTrue, _colorFalse)
                        if color then
                            s:SetAlpha(color.a)
                        else
                            s:SetAlpha(0)
                        end
                    else
                        s:SetAlpha((stealable == true) and 1 or 0)
                    end
                else
                    s:SetAlpha(0)
                end
            end
        until not cont
        -- Hide excess sentinels from previous scan
        local pool = uf._msufPurgeSentinels
        if pool then
            for idx = sentIdx + 1, #pool do
                pool[idx]:SetAlpha(0)
            end
        end
        local changed = (uf._msufPurgeOutlineOn == true) ~= (purgeOn == true)
        uf._msufPurgeOutlineOn = purgeOn and true or nil
        return changed
    end

    local function HideAllPurgeSentinels(uf)
        local pool = uf._msufPurgeSentinels
        if pool then
            for i = 1, #pool do
                pool[i]:SetAlpha(0)
            end
        end
        local changed = uf and uf._msufPurgeOutlineOn == true
        if uf then uf._msufPurgeOutlineOn = nil end
        return changed
    end

    local function UpdateUnit(unit, forceRefresh)
        local uf = _ResolveUnitFrame(unit)
        if not _FrameMatchesUnit(uf, unit) then return end

        local cfg = _RefreshBorderSettingsForFrame(uf)
        local dispelEnabled = (cfg.dispelOutlineMode == 1)
        local overlayEnabled = (cfg.unitDispelOverlayEnabled == true)
        local purgeEnabled  = (cfg.purgeOutlineMode  == 1)
        local dispelTrigger = cfg.dispelBorderTrigger or DISPEL_TRIGGER_BY_ME
        local overlayTrigger = _ResolveUnitDispelOverlayTrigger(cfg)

        local dispelOn = false
        local overlayOn = false
        -- BY_ME is friendly/class gated; DISPEL_TYPE and ANY_DEBUFF are
        -- plain harmful scans so target/focus unit frames can use them too.
        -- Purge remains attackable-only.
        local canAttack = UnitCanAttack and UnitCanAttack("player", unit)
        local dispelAid, dispelType
        local overlayAid, overlayType
        local borderNeedsScan = dispelEnabled and _UnitCanScanDispelTriggerVisual(unit, dispelTrigger, cfg, false)
        local overlayNeedsScan = overlayEnabled and _UnitCanScanDispelTriggerVisual(unit, overlayTrigger, cfg, true)
        local canShareScan = borderNeedsScan and overlayNeedsScan
            and dispelTrigger == overlayTrigger
            and _UFDispelScanPrioritySignature(cfg, false) == _UFDispelScanPrioritySignature(cfg, true)
            and _UFDispelScanResolveType(cfg, false, dispelTrigger) == _UFDispelScanResolveType(cfg, true, overlayTrigger)
        if canShareScan then
            local sharedOn, sharedAid, sharedType = HasDispellableDebuff(unit, dispelTrigger, cfg, false)
            dispelOn, dispelAid, dispelType = sharedOn, sharedAid, sharedType
            overlayOn, overlayAid, overlayType = sharedOn, sharedAid, sharedType
        else
            if borderNeedsScan then
                dispelOn, dispelAid, dispelType = HasDispellableDebuff(unit, dispelTrigger, cfg, false)
            end
            if overlayNeedsScan then
                overlayOn, overlayAid, overlayType = HasDispellableDebuff(unit, overlayTrigger, cfg, true)
            end
        end

        -- Purge: sentinel frames handle rendering via SetAlpha with secret values.
        -- Secret constraints prevent boolean tracking ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â sentinels ARE the border.
        -- Purge participates in highlight priority only via test mode.
        local purgeChanged = false
        if purgeEnabled and canAttack and unit ~= "player" and PlayerMayPurge() then
            purgeChanged = UpdatePurgeSentinels(uf, unit, cfg) == true
        else
            purgeChanged = HideAllPurgeSentinels(uf) == true
        end

        local changed = false
        if forceRefresh or uf._msufDispelOutlineOn ~= dispelOn or uf._msufDispelAuraID ~= dispelAid or uf._msufDispelType ~= dispelType then
            uf._msufDispelOutlineOn = dispelOn
            uf._msufDispelAuraID = dispelAid
            uf._msufDispelType = dispelType
            changed = true
        end

        local overlayChanged = false
        if forceRefresh
            or uf._msufUFDispelOverlayOn ~= overlayOn
            or uf._msufUFDispelOverlayAuraID ~= overlayAid
            or uf._msufUFDispelOverlayType ~= overlayType then
            uf._msufUFDispelOverlayOn = overlayOn
            uf._msufUFDispelOverlayAuraID = overlayAid
            uf._msufUFDispelOverlayType = overlayType
            overlayChanged = true
        end

        if changed or purgeChanged then
            if _G.MSUF_RefreshRareBarVisuals then
                _G.MSUF_RefreshRareBarVisuals(uf)
            end
        end
        if overlayChanged then
            _ApplyUFDispelOverlay(uf, cfg)
        end
    end

    _G.MSUF_RefreshDispelOutlineStates = function(forceRefresh)
        if forceRefresh then ClearDispelScanCache() end
        UpdateUnit("player", forceRefresh)
        UpdateUnit("target", true)
        UpdateUnit("focus", true)
        UpdateUnit("targettarget", true)
    end

    local _dispelAuraQueued = {}
    local _dispelAuraUnits = {}
    local _dispelAuraUnitsN = 0
    local _dispelAuraFlushQueued = false
    local _dispelAuraWant = false
    local _friendlyDispelAuraWant = false
    local _purgeAuraWant = false
    local function UnitWantsFriendlyDispelBorder(unit)
        if not _OutlineModeEnabledForUnit(unit, "dispelOutlineMode", "hlDispelEnabled") then
            return false, DISPEL_TRIGGER_BY_ME
        end

        local uf = _ResolveUnitFrame(unit)
        local cfg = uf and _RefreshBorderSettingsForFrame(uf)
        local mode = (cfg and cfg.dispelBorderTrigger) or _RefreshBorderSettingsCache().dispelBorderTrigger or DISPEL_TRIGGER_BY_ME
        mode = _NormalizeDispelBorderTrigger(mode)
        if _DispelBorderTriggerNeedsPlayerDispel(mode)
            and not PlayerMayFriendlyDispel()
            and not _UFDispelScanCustomTypePriorityEnabled(cfg, false)
        then
            return false, mode
        end
        return true, mode
    end

    local function UnitWantsFriendlyDispelOverlay(unit)
        local uf = _ResolveUnitFrame(unit)
        local cfg = uf and _RefreshBorderSettingsForFrame(uf)
        local enabled, mode
        if cfg then
            enabled = cfg.unitDispelOverlayEnabled == true
            mode = _ResolveUnitDispelOverlayTrigger(cfg)
        else
            local base = _RefreshBorderSettingsCache()
            local db = _GetUnitBorderScopeDB(unit)
            if db and db.unitDispelOverlayEnabled ~= nil then
                enabled = db.unitDispelOverlayEnabled == true
            else
                enabled = base and base.unitDispelOverlayEnabled == true
            end
            mode = _NormalizeUnitDispelOverlayTrigger((db and db.unitDispelOverlayTrigger) or (base and base.unitDispelOverlayTrigger))
            if mode == DISPEL_TRIGGER_BORDER then
                mode = _NormalizeDispelBorderTrigger((db and db.dispelBorderTrigger) or (base and base.dispelBorderTrigger))
            end
        end
        if not enabled then
            return false, DISPEL_TRIGGER_BY_ME
        end
        if _DispelBorderTriggerNeedsPlayerDispel(mode)
            and not PlayerMayFriendlyDispel()
            and not _UFDispelScanCustomTypePriorityEnabled(cfg, true)
        then
            return false, mode
        end
        return true, mode
    end

    local function UnitWantsFriendlyDispelVisual(unit)
        local uf = _ResolveUnitFrame(unit)
        if uf then
            local cfg = _RefreshBorderSettingsForFrame(uf)
            local borderMode = (cfg and cfg.dispelBorderTrigger) or DISPEL_TRIGGER_BY_ME
            local overlayMode = cfg and _ResolveUnitDispelOverlayTrigger(cfg) or DISPEL_TRIGGER_BY_ME
            local borderWants = cfg and cfg.dispelOutlineMode == 1
            local overlayWants = cfg and cfg.unitDispelOverlayEnabled == true
            if borderWants and _DispelBorderTriggerNeedsPlayerDispel(borderMode)
                and not PlayerMayFriendlyDispel()
                and not _UFDispelScanCustomTypePriorityEnabled(cfg, false)
            then
                borderWants = false
            end
            if overlayWants and _DispelBorderTriggerNeedsPlayerDispel(overlayMode)
                and not PlayerMayFriendlyDispel()
                and not _UFDispelScanCustomTypePriorityEnabled(cfg, true)
            then
                overlayWants = false
            end
            return (borderWants or overlayWants), borderWants and borderMode or nil, overlayWants and overlayMode or nil, uf, cfg
        end

        local borderWants, borderMode = UnitWantsFriendlyDispelBorder(unit)
        local overlayWants, overlayMode = UnitWantsFriendlyDispelOverlay(unit)
        return (borderWants or overlayWants), borderWants and borderMode or nil, overlayWants and overlayMode or nil
    end

    local function ResolveDispelAuraEventWants()
        local friendlyDispel = false
        friendlyDispel = UnitWantsFriendlyDispelVisual("player")
            or UnitWantsFriendlyDispelVisual("target")
            or UnitWantsFriendlyDispelVisual("focus")
            or UnitWantsFriendlyDispelVisual("targettarget")
        local purge = false
        if PlayerMayPurge() then
            purge = _OutlineModeEnabledForUnit("target", "purgeOutlineMode")
                or _OutlineModeEnabledForUnit("focus", "purgeOutlineMode")
                or _OutlineModeEnabledForUnit("targettarget", "purgeOutlineMode")
        end
        return (purge or friendlyDispel), friendlyDispel, purge
    end

    local ApplyDispelOutlineEventRegistration

    local function FlushDispelAuraUnits()
        _dispelAuraFlushQueued = false
        for i = 1, _dispelAuraUnitsN do
            local u = _dispelAuraUnits[i]
            _dispelAuraUnits[i] = nil
            if u then
                _dispelAuraQueued[u] = nil
                UpdateUnit(u, false)
            end
        end
        _dispelAuraUnitsN = 0
    end
    local function QueueDispelAuraUnit(unit)
        if not unit then return end
        if _dispelAuraQueued[unit] then return end
        ClearDispelScanCache(unit)
        _dispelAuraQueued[unit] = true
        _dispelAuraUnitsN = _dispelAuraUnitsN + 1
        _dispelAuraUnits[_dispelAuraUnitsN] = unit
        if not _dispelAuraFlushQueued then
            _dispelAuraFlushQueued = true
            if C_Timer and C_Timer.After then
                C_Timer.After(0, FlushDispelAuraUnits)
            else
                FlushDispelAuraUnits()
            end
        end
    end

    local function AuraDataMayAffectFriendlyDispel(aura, triggerMode)
        if type(aura) ~= "table" then return true end
        triggerMode = _NormalizeDispelBorderTrigger(triggerMode)

        local dn = aura.dispelName
        if issecretvalue and issecretvalue(dn) then return true end
        if triggerMode == DISPEL_TRIGGER_ANY then
            local harmfulAny = aura.isHarmful
            if issecretvalue and issecretvalue(harmfulAny) then return true end
            if harmfulAny == true then return true end
            if harmfulAny == false then return false end
            return true
        end
        if triggerMode == DISPEL_TRIGGER_TYPE then
            if type(dn) == "string" then
                return dn ~= "" and dn ~= "None"
            end
            local harmfulType = aura.isHarmful
            if issecretvalue and issecretvalue(harmfulType) then return true end
            return harmfulType == true
        end
        if type(dn) == "string" then
            return dn ~= "" and dn ~= "None"
        end

        local harmful = aura.isHarmful
        if issecretvalue and issecretvalue(harmful) then return true end
        if harmful == true then return true end
        if harmful == false then return false end

        return true
    end

    local function UpdateInfoMayAffectFriendlyDispel(unit, updateInfo, unitWants, borderTriggerMode, overlayTriggerMode, uf, cfg)
        if type(updateInfo) ~= "table" or updateInfo.isFullUpdate then return true end
        if unitWants == nil then
            unitWants, borderTriggerMode, overlayTriggerMode, uf, cfg = UnitWantsFriendlyDispelVisual(unit)
        end
        if not unitWants then return false end
        uf = uf or _ResolveUnitFrame(unit)
        cfg = cfg or (uf and _RefreshBorderSettingsForFrame(uf))
        local priorityScan = cfg and (
            (borderTriggerMode and _UFDispelScanPriorityEnabled(cfg, false))
            or (overlayTriggerMode and _UFDispelScanPriorityEnabled(cfg, true))
            or (borderTriggerMode and _UFDispelScanCustomTypePriorityEnabled(cfg, false))
            or (overlayTriggerMode and _UFDispelScanCustomTypePriorityEnabled(cfg, true))
        )
        if priorityScan then
            return true
        end

        local added = updateInfo.addedAuras
        if added then
            for i = 1, #added do
                local aura = added[i]
                if borderTriggerMode and AuraDataMayAffectFriendlyDispel(aura, borderTriggerMode) then return true end
                if overlayTriggerMode and overlayTriggerMode ~= borderTriggerMode and AuraDataMayAffectFriendlyDispel(aura, overlayTriggerMode) then return true end
            end
        end

        local updated = updateInfo.updatedAuraInstanceIDs
        if updated and #updated > 0 then
            uf = _ResolveUnitFrame(unit)
            local borderAid = uf and uf._msufDispelAuraID
            local overlayAid = uf and uf._msufUFDispelOverlayAuraID
            if borderAid or overlayAid then
                for i = 1, #updated do
                    local aid = updated[i]
                    if aid == borderAid or aid == overlayAid then return true end
                end
            end
            return false
        end

        local removed = updateInfo.removedAuraInstanceIDs
        if removed and #removed > 0 then
            uf = uf or _ResolveUnitFrame(unit)
            return uf and (
                uf._msufDispelOutlineOn or uf._msufDispelAuraID ~= nil
                or uf._msufUFDispelOverlayOn or uf._msufUFDispelOverlayAuraID ~= nil
            ) or false
        end

        return false
    end

    local function AuraDataMayAffectPurge(aura)
        if type(aura) ~= "table" then return true end

        local helpful = aura.isHelpful
        if issecretvalue and issecretvalue(helpful) then return true end
        if helpful == true then return true end
        if helpful == false then return false end

        local harmful = aura.isHarmful
        if issecretvalue and issecretvalue(harmful) then return true end
        if harmful == true then return false end

        return true
    end

    local function UpdateInfoMayAffectPurge(updateInfo)
        if type(updateInfo) ~= "table" or updateInfo.isFullUpdate then return true end

        local added = updateInfo.addedAuras
        if added then
            for i = 1, #added do
                if AuraDataMayAffectPurge(added[i]) then return true end
            end
        end

        local removed = updateInfo.removedAuraInstanceIDs
        if removed and #removed > 0 then return true end

        local updated = updateInfo.updatedAuraInstanceIDs
        if updated and #updated > 0 then return true end

        return false
    end

    f:SetScript("OnEvent", function(_, event, unit, updateInfo)
        if event == "UNIT_AURA" then
            if unit ~= "player" and unit ~= "target" and unit ~= "focus" and unit ~= "targettarget" then return end
            if not _dispelAuraWant or _dispelAuraQueued[unit] then return end
            local shouldQueue = false
            if _friendlyDispelAuraWant then
                local unitWants, borderMode, overlayMode, uf, cfg = UnitWantsFriendlyDispelVisual(unit)
                if unitWants
                    and ((borderMode and _UnitCanScanDispelTriggerVisual(unit, borderMode, cfg, false))
                        or (overlayMode and _UnitCanScanDispelTriggerVisual(unit, overlayMode, cfg, true)))
                then
                    shouldQueue = UpdateInfoMayAffectFriendlyDispel(unit, updateInfo, unitWants, borderMode, overlayMode, uf, cfg)
                end
            end
            if not shouldQueue and _purgeAuraWant and unit ~= "player" and UnitCanAttack and UnitCanAttack("player", unit) then
                shouldQueue = UpdateInfoMayAffectPurge(updateInfo)
            end
            if not shouldQueue then return end
            QueueDispelAuraUnit(unit)
            return
        end

        -- Init / safety clear so state is correct without requiring Edit Mode / manual refresh.
        if event == "PLAYER_ENTERING_WORLD" then
            ClearDispelScanCache()
            ClearFriendlyDispelCapabilityCache()
            ApplyDispelOutlineEventRegistration()
            _G.MSUF_RefreshDispelOutlineStates(true)
            return
        end
    end)
    ApplyDispelOutlineEventRegistration = function()
        local want, friendlyDispelWant, purgeWant = ResolveDispelAuraEventWants()
        _dispelAuraWant = want
        _friendlyDispelAuraWant = friendlyDispelWant
        _purgeAuraWant = purgeWant

        if want then
            if not f:IsEventRegistered("PLAYER_ENTERING_WORLD") then
                f:RegisterEvent("PLAYER_ENTERING_WORLD")
            end
            if f.RegisterUnitEvent then
                if not f:IsEventRegistered("UNIT_AURA") then
                    f:RegisterUnitEvent("UNIT_AURA", "player", "target", "focus", "targettarget")
                end
            elseif not f:IsEventRegistered("UNIT_AURA") then
                f:RegisterEvent("UNIT_AURA")
            end
            do
                local _qDTgt, _qDFoc
                local function ForceVisualTest()
                    return _G.MSUF_BorderTestModesActive == true
                        and (_G.MSUF_DispelBorderTestMode == true or _G.MSUF_PurgeBorderTestMode == true)
                end
                local function _flushDTgt()
                    _qDTgt = nil
                    ClearDispelScanCache("target")
                    ClearDispelScanCache("targettarget")
                    local force = ForceVisualTest()
                    UpdateUnit("target", force)
                    UpdateUnit("targettarget", force)
                end
                local function _flushDFoc()
                    _qDFoc = nil
                    ClearDispelScanCache("focus")
                    UpdateUnit("focus", ForceVisualTest())
                end
                MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_DISPEL_OUTLINE", function()
                    if not _qDTgt then _qDTgt = true; if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("BORDER_DISPEL_TARGET", _flushDTgt) else C_Timer.After(0, _flushDTgt) end end
                end)
                MSUF_EventBus_Register("PLAYER_FOCUS_CHANGED", "MSUF_DISPEL_OUTLINE", function()
                    if not _qDFoc then _qDFoc = true; if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("BORDER_DISPEL_FOCUS", _flushDFoc) else C_Timer.After(0, _flushDFoc) end end
                end)
            end
        else
            if f:IsEventRegistered("PLAYER_ENTERING_WORLD") then
                f:UnregisterEvent("PLAYER_ENTERING_WORLD")
            end
            if f:IsEventRegistered("UNIT_AURA") then
                f:UnregisterEvent("UNIT_AURA")
            end
            if type(MSUF_EventBus_Unregister) == "function" then
                MSUF_EventBus_Unregister("PLAYER_TARGET_CHANGED", "MSUF_DISPEL_OUTLINE")
                MSUF_EventBus_Unregister("PLAYER_FOCUS_CHANGED", "MSUF_DISPEL_OUTLINE")
            end
        end
    end

    _G.MSUF_DispelOutline_ApplyEventRegistration = ApplyDispelOutlineEventRegistration
    ApplyDispelOutlineEventRegistration()
end

do
    local f = F.CreateFrame("Frame")
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:RegisterEvent("DISPLAY_SIZE_CHANGED")
    f:SetScript("OnEvent", function()
        if _G.MSUF_UpdatePixelPerfect then
            _G.MSUF_UpdatePixelPerfect()
    end
        if MSUF_BarBorderCache then
            MSUF_BarBorderCache.stamp = nil
    end
        MSUF_ForEachUnitFrame(_Iter_ResetBorderOnScale)
_G.MSUF_UpdateCastbarVisuals()
     end)
end
