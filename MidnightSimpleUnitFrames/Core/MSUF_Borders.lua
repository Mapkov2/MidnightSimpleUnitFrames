-- Core/MSUF_Borders.lua  Aggro / Dispel / Purge border system + UI_SCALE handler
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...

local F = ns.Cache and ns.Cache.F or {}
F.CreateFrame = F.CreateFrame or CreateFrame
local type, tonumber, ipairs, pairs = type, tonumber, ipairs, pairs
local MSUF_TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"
local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown

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

local function _StopDispelGlowOn(anchor)
    if not (LCG and anchor) then return end
    LCG.PixelGlow_Stop(anchor, "msufDispel")
    LCG.AutoCastGlow_Stop(anchor, "msufDispel")
    LCG.ProcGlow_Stop(anchor, "msufDispel")
end

local function _StartDispelGlow(frame, r, g, b, cfg)
    if not LCG then return end
    local anchor = frame._msufHighlightOutline or frame
    local style = cfg.dispelGlowStyle or "PIXEL"
    local oldAnchor = frame._msufDispelGlowAnchor
    if oldAnchor and (oldAnchor ~= anchor or frame._msufDispelGlowStyle ~= style) then
        _StopDispelGlowOn(oldAnchor)
    end
    if anchor ~= frame then
        _StopDispelGlowOn(frame)
    end
    _glowColorTbl[1], _glowColorTbl[2], _glowColorTbl[3] = r, g, b
    if style == "AUTOCAST" then
        LCG.AutoCastGlow_Start(anchor, _glowColorTbl, cfg.dispelGlowLines, cfg.dispelGlowFreq, nil, nil, nil, "msufDispel")
    elseif style == "PROC" then
        LCG.ProcGlow_Start(anchor, { color = _glowColorTbl, key = "msufDispel" })
    else -- PIXEL default
        LCG.PixelGlow_Start(anchor, _glowColorTbl, cfg.dispelGlowLines, cfg.dispelGlowFreq, nil, cfg.dispelGlowThick, nil, nil, nil, "msufDispel")
    end
    frame._msufDispelGlowActive = true
    frame._msufDispelGlowAnchor = anchor
    frame._msufDispelGlowStyle = style
end

local function _StopDispelGlow(frame)
    if not frame then return end
    frame._msufDispelGlowActive = nil
    local anchor = frame._msufDispelGlowAnchor
    frame._msufDispelGlowAnchor = nil
    frame._msufDispelGlowStyle = nil
    _StopDispelGlowOn(anchor)

    local outline = frame._msufHighlightOutline
    if outline and outline ~= anchor then
        _StopDispelGlowOn(outline)
    end
    if frame ~= anchor and frame ~= outline then
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
        value = db and db[legacyKey]
    end
    return _Clamp01(value, fallback)
end

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
    _borderCfg.dispelOutlineMode = _ReadOutlineMode(g, "dispelOutlineMode", "hlDispelEnabled", 0)
    _borderCfg.purgeOutlineMode = _ReadOutlineMode(g, "purgeOutlineMode", nil, 0)
    _borderCfg.bossTargetOutlineMode = _ReadOutlineMode(g, "bossTargetOutlineMode", nil, ((g and g.bossTargetHighlightEnabled ~= false) and 1 or 0))
    _borderCfg.highlightBorderThickness = tonumber(g and g.highlightBorderThickness) or 2
    if _borderCfg.highlightBorderThickness < 1 then _borderCfg.highlightBorderThickness = 1 end
    _borderCfg.dispelColorMode = (g and g.hlDispelColorMode) or "SINGLE"
    local prioEnabled = g and g.hlPrioEnabled
    if prioEnabled == nil then prioEnabled = g and (g.highlightPrioEnabled == 1) end
    _borderCfg.highlightPrioEnabled = (prioEnabled == true)
    _borderCfg.highlightPrioOrder = (g and type(g.hlPrioOrder) == "table" and g.hlPrioOrder)
        or (g and type(g.highlightPrioOrder) == "table" and g.highlightPrioOrder)
        or nil
    _borderCfg.aggroR  = _ReadColorValue(g, "hlAggroColorR",  "aggroBorderColorR",  1.00)
    _borderCfg.aggroG  = _ReadColorValue(g, "hlAggroColorG",  "aggroBorderColorG",  0.50)
    _borderCfg.aggroB  = _ReadColorValue(g, "hlAggroColorB",  "aggroBorderColorB",  0.00)
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

local function _RefreshBorderSettingsForFrame(frame)
    local base = _RefreshBorderSettingsCache()
    local db = _GetUnitBorderScopeDB(frame and frame.unit)
    if not db then return base end

    local cfg = _CopyBorderCfg(_scopedBorderCfg, base)
    cfg.aggroOutlineMode = _ReadOutlineMode(db, "aggroOutlineMode", "hlAggroEnabled", base.aggroOutlineMode)
    cfg.dispelOutlineMode = _ReadOutlineMode(db, "dispelOutlineMode", "hlDispelEnabled", base.dispelOutlineMode)
    cfg.purgeOutlineMode = _ReadOutlineMode(db, "purgeOutlineMode", nil, base.purgeOutlineMode)
    cfg.bossTargetOutlineMode = _ReadOutlineMode(db, "bossTargetOutlineMode", nil, base.bossTargetOutlineMode)

    cfg.highlightBorderThickness = tonumber(db.highlightBorderThickness or db.hlAggroSize) or base.highlightBorderThickness
    if cfg.highlightBorderThickness < 1 then cfg.highlightBorderThickness = 1 end
    cfg.dispelColorMode = db.hlDispelColorMode or base.dispelColorMode

    if db.hlPrioEnabled ~= nil then
        cfg.highlightPrioEnabled = (db.hlPrioEnabled == true)
    elseif db.highlightPrioEnabled ~= nil then
        cfg.highlightPrioEnabled = (db.highlightPrioEnabled == 1 or db.highlightPrioEnabled == true)
    end
    if type(db.hlPrioOrder) == "table" then
        cfg.highlightPrioOrder = db.hlPrioOrder
    elseif type(db.highlightPrioOrder) == "table" then
        cfg.highlightPrioOrder = db.highlightPrioOrder
    end

    cfg.aggroR  = _ReadColorValue(db, "hlAggroColorR",  "aggroBorderColorR",  base.aggroR)
    cfg.aggroG  = _ReadColorValue(db, "hlAggroColorG",  "aggroBorderColorG",  base.aggroG)
    cfg.aggroB  = _ReadColorValue(db, "hlAggroColorB",  "aggroBorderColorB",  base.aggroB)
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

local function _Iter_SyncBorderStamps(uf)
    if not uf or not uf.unit then return end
    local thickness, stamp = 0, 0
    local get = MSUF_GetDesiredBarBorderThicknessAndStamp
    if type(get) == "function" then
        thickness, stamp = get(uf)
    end
    uf._msufBarBorderStamp = stamp
    uf._msufBarOutlineThickness = thickness
    uf._msufBarOutlineEdgeSize = -1
    uf._msufHighlightEdgeSize = -1
    uf._msufHighlightColorKey = -1
    uf._msufHighlightBottomIsPower = nil
    local pb = uf.targetPowerBar
    local pbDetached = uf._msufPowerBarDetached
    uf._msufBarOutlineBottomIsPower = (pb and not pbDetached and pb.IsShown and pb:IsShown()) and true or false
    local apply = _G.MSUF_RefreshRareBarVisuals
    if type(apply) == "function" then apply(uf) end
end

local function _Iter_ResetBorderOnScale(uf)
    if uf and uf.unit then
        uf._msufBarBorderStamp = nil
        uf._msufBarOutlineEdgeSize = -1
        if _G.MSUF_QueueUnitframeVisual then
            _G.MSUF_QueueUnitframeVisual(uf)
        end
    end
end

local MSUF_ApplyRareVisuals
-- Aggro outline indicator: reuse the bar-outline border and recolor/thicken it
-- when the player has full aggro on target/focus/boss frames.
local function MSUF_IsAggroOutlineUnit(unit)
    if unit == "target" or unit == "focus" then return true end
    if type(unit) == "string" and unit:sub(1, 4) == "boss" then
        local n = tonumber(unit:sub(5))
        if n and n >= 1 and n <= 5 then return true end
    end
    return false
end
local _UF_DISPEL_INDEX_BY_NAME = { Magic = 1, Curse = 2, Disease = 3, Poison = 4, Bleed = 5, None = 0 }

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
local function _GetUFDispelColor(dispelName, unit, auraID, cfg)
    local g = MSUF_DB and MSUF_DB.general
    local mode = (cfg and cfg.dispelColorMode) or (g and g.hlDispelColorMode) or "SINGLE"
    if mode ~= "TYPE" then
        if cfg then
            return cfg.dispelR or 0.25, cfg.dispelG or 0.75, cfg.dispelB or 1.00
        end
        return _ReadColorValue(g, "hlDispelColorR", "dispelBorderColorR", 0.25),
               _ReadColorValue(g, "hlDispelColorG", "dispelBorderColorG", 0.75),
               _ReadColorValue(g, "hlDispelColorB", "dispelBorderColorB", 1.00)
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
    if issecretvalue and issecretvalue(dispelName) then
        dispelName = nil
    end
    if dispelName == "DISPELLABLE" then dispelName = nil end
    if type(dispelName) == "string" then
        local r = g and g["dispelType" .. dispelName .. "R"]
        if type(r) == "number" then
            return r, g["dispelType" .. dispelName .. "G"], g["dispelType" .. dispelName .. "B"]
        end
        local idx = _UF_DISPEL_INDEX_BY_NAME[dispelName or "None"] or 0
        local obj = ({
            [1] = _G.DEBUFF_TYPE_MAGIC_COLOR,
            [2] = _G.DEBUFF_TYPE_CURSE_COLOR,
            [3] = _G.DEBUFF_TYPE_DISEASE_COLOR,
            [4] = _G.DEBUFF_TYPE_POISON_COLOR,
            [5] = _G.DEBUFF_TYPE_BLEED_COLOR,
            [0] = _G.DEBUFF_TYPE_NONE_COLOR,
        })[idx]
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
    end

    if cfg then
        return cfg.dispelR or 0.25, cfg.dispelG or 0.75, cfg.dispelB or 1.00
    end
    return _ReadColorValue(g, "hlDispelColorR", "dispelBorderColorR", 0.25),
           _ReadColorValue(g, "hlDispelColorG", "dispelBorderColorG", 0.75),
           _ReadColorValue(g, "hlDispelColorB", "dispelBorderColorB", 1.00)
end

local function _ApplyUFBarBorderTint(self, showTint, r, g, b)
    local o = self and self._msufBarOutline
    local f = o and o.frame
    if not f then return end
    if showTint then
        f:SetBackdropBorderColor(r or 0, g or 0, b or 0, 1)
    else
        f:SetBackdropBorderColor(0, 0, 0, 1)
    end
end

local function MSUF_ReadDetachedPowerBarBorder(self)
    local unitKey = self and (self.msufConfigKey or self.unit)
    local readEnabled = _G.MSUF_ReadUnitPowerBarBorderEnabled
    local readSize = _G.MSUF_ReadUnitPowerBarBorderThickness
    local barsDB = MSUF_DB and MSUF_DB.bars

    local enabled
    if type(readEnabled) == "function" then
        enabled = readEnabled(unitKey)
    else
        enabled = barsDB and (barsDB.powerBarBorderEnabled == true) or false
    end

    local thickness
    if type(readSize) == "function" then
        thickness = readSize(unitKey)
    else
        thickness = barsDB and tonumber(barsDB.powerBarBorderThickness or barsDB.powerBarBorderSize) or 1
    end
    local detachedOverride = barsDB and barsDB.detachedPowerBarOutline
    if detachedOverride ~= nil then
        local override = tonumber(detachedOverride)
        if override ~= nil then thickness = override end
    end
    thickness = tonumber(thickness) or 1
    if thickness < 0 then thickness = 0 elseif thickness > 6 then thickness = 6 end
    return enabled == true, thickness
end

local function MSUF_ApplyDetachedPowerBarOutline(self)
    local pb = self and self.targetPowerBar
    local outline = self and self._msufDetachedPBOutline
    if not (self and pb and self._msufPowerBarDetached and pb.IsShown and pb:IsShown()) then
        if outline then outline:Hide() end
        return
    end

    local enabled, thickness = MSUF_ReadDetachedPowerBarBorder(self)
    if not enabled or thickness <= 0 then
        if outline then outline:Hide() end
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

    local snap = _G.MSUF_Snap
    local edge = (type(snap) == "function") and snap(outline, thickness) or thickness
    if outline._msufLastEdgeSize ~= edge then
        outline:SetBackdrop({ edgeFile = MSUF_TEX_WHITE8, edgeSize = edge })
        outline:SetBackdropBorderColor(0, 0, 0, 1)
        outline._msufLastEdgeSize = edge
        outline._msufDetachedPBStamp = nil
    end

    local stamp = tostring(edge) .. ":" .. tostring(frameLevel)
    if outline._msufDetachedPBStamp ~= stamp then
        outline:ClearAllPoints()
        outline:SetPoint("TOPLEFT", pb, "TOPLEFT", -edge, edge)
        outline:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", edge, -edge)
        outline._msufDetachedPBStamp = stamp
    end
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
    end
    local hb = self.hpBar
    local pb = self.targetPowerBar
    local pbDetached = self._msufPowerBarDetached
    local pbWanted = (pb ~= nil) and not pbDetached and (self._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
    local bottomBar = pbWanted and pb or hb
    local bottomIsPower = pbWanted and true or false
    local f = o.frame
    local snap = _G.MSUF_Snap
    local edge = (type(snap) == "function") and snap(f, thickness) or thickness

    if o._msufLastEdgeSize ~= edge then
        f:SetBackdrop({ edgeFile = MSUF_TEX_WHITE8, edgeSize = edge })
        f:SetBackdropBorderColor(0, 0, 0, 1)
        o._msufLastEdgeSize = edge
        self._msufBarOutlineEdgeSize = -1
    end

    if (self._msufBarOutlineThickness ~= thickness) or (self._msufBarOutlineEdgeSize ~= edge) or (self._msufBarOutlineBottomIsPower ~= (bottomIsPower and true or false)) then
        f:ClearAllPoints()
        if hb then
            f:SetPoint("TOPLEFT", hb, "TOPLEFT", -edge, edge)
        end
        if bottomBar then
            f:SetPoint("BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", edge, -edge)
        end
        self._msufBarOutlineThickness = thickness
        self._msufBarOutlineEdgeSize = edge
        self._msufBarOutlineBottomIsPower = bottomIsPower and true or false
    end
    f:Show()
    if self._msufBarBorderTintActive then
        f:SetBackdropBorderColor(self._msufBarBorderTintR or 0, self._msufBarBorderTintG or 0, self._msufBarBorderTintB or 0, 1)
    else
        f:SetBackdropBorderColor(0, 0, 0, 1)
    end

    MSUF_ApplyDetachedPowerBarOutline(self)
end

-- Sub-function: create/update highlight overlay frame for aggro/dispel/purge.
local function MSUF_ApplyHighlightOverlay(self, hlKey, hlR, hlG, hlB, cfg)
    local hlFrame = self._msufHighlightOutline

    if hlKey == 0 then
        _StopDispelGlow(self)
        if hlFrame then hlFrame:Hide() end
        self._msufHighlightColorKey = 0
        return
    end

    local hlThickness = (cfg and cfg.highlightBorderThickness) or 2

    if not hlFrame then
        local template = (BackdropTemplateMixin and "BackdropTemplate") or nil
        hlFrame = F.CreateFrame("Frame", nil, self, template)
        hlFrame:EnableMouse(false)
        hlFrame:SetFrameStrata(self:GetFrameStrata())
        local baseLevel = self:GetFrameLevel() + 3
        if self.hpBar and self.hpBar.GetFrameLevel then
            baseLevel = self.hpBar:GetFrameLevel() + 3
        end
        hlFrame:SetFrameLevel(baseLevel)
        self._msufHighlightOutline = hlFrame
        self._msufHighlightEdgeSize = -1
        self._msufHighlightColorKey = -1
        self._msufHighlightBottomIsPower = nil
    end

    local hb = self.hpBar
    local pb = self.targetPowerBar
    local pbDetached = self._msufPowerBarDetached
    local pbWanted = (pb ~= nil) and not pbDetached and (self._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
    local bottomBar = pbWanted and pb or hb
    local bottomIsPower = pbWanted and true or false
    local snap = _G.MSUF_Snap
    local hlEdge = (type(snap) == "function") and snap(hlFrame, hlThickness) or hlThickness

    if self._msufHighlightEdgeSize ~= hlEdge then
        hlFrame:SetBackdrop({ edgeFile = MSUF_TEX_WHITE8, edgeSize = hlEdge })
        self._msufHighlightEdgeSize = hlEdge
        self._msufHighlightColorKey = -1  -- force recolor
        self._msufHighlightBottomIsPower = nil  -- force re-anchor with new offset
    end

    if self._msufHighlightColorKey ~= hlKey then
        hlFrame:SetBackdropBorderColor(hlR, hlG, hlB, 1)
        self._msufHighlightColorKey = hlKey
    end

    if self._msufHighlightBottomIsPower ~= bottomIsPower then
        hlFrame:ClearAllPoints()
        if hb then
            hlFrame:SetPoint("TOPLEFT", hb, "TOPLEFT", -hlEdge, hlEdge)
        end
        if bottomBar then
            hlFrame:SetPoint("BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", hlEdge, -hlEdge)
        end
        self._msufHighlightBottomIsPower = bottomIsPower
    end

    -- Start only after the highlight frame exists, so Stop uses the same anchor.
    if hlKey == 2 and cfg.dispelGlowEnabled then
        _StartDispelGlow(self, hlR, hlG, hlB, cfg)
    else
        _StopDispelGlow(self)
    end

    hlFrame:Show()
end

MSUF_ApplyRareVisuals = function(self)
    if not self or not self.unit then  return end
    if self.border then
        self.border:Hide()
    end
    local baseThickness = 0
    if type(MSUF_GetDesiredBarBorderThicknessAndStamp) == "function" then
        baseThickness = select(1, MSUF_GetDesiredBarBorderThicknessAndStamp(self))
    end
    baseThickness = tonumber(baseThickness) or 0

    local cfg = _RefreshBorderSettingsForFrame(self)

    -- Aggro state detection (target/focus/boss only).
    local borderTestsActive = _G.MSUF_BorderTestModesActive == true
    local aggroTest = borderTestsActive and _G.MSUF_AggroBorderTestMode and true or false
    if aggroTest then
        local testScope = _G.MSUF_AggroBorderTestScope or "shared"
        local u = self.unit
        if testScope == "party" or testScope == "raid" or testScope == "mythicraid" or testScope == "gf_party" or testScope == "gf_raid" or testScope == "gf_mythicraid" then
            aggroTest = false
        elseif testScope ~= "shared" and not (testScope == "boss" and type(u) == "string" and u:sub(1, 4) == "boss") and u ~= testScope then
            aggroTest = false
        end
    end
    local wantAggro = MSUF_IsAggroOutlineUnit(self.unit) and ((cfg.aggroOutlineMode == 1) or aggroTest)
    local threat = false
    if wantAggro then
        if aggroTest then
            threat = true
        elseif UnitThreatSituation then
            local raw = UnitThreatSituation("player", self.unit)
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

    local aggroR, aggroG, aggroB = cfg.aggroR, cfg.aggroG, cfg.aggroB
    local dispelR, dispelG, dispelB = _GetUFDispelColor(self._msufDispelType, self.unit, self._msufDispelAuraID, cfg)
    local purgeR, purgeG, purgeB = cfg.purgeR, cfg.purgeG, cfg.purgeB
    local bossTargetR, bossTargetG, bossTargetB = cfg.bossTargetR, cfg.bossTargetG, cfg.bossTargetB

    -- Dispel state detection.
    local dispel = false
    do
        local test = borderTestsActive and (_G.MSUF_DispelBorderTestMode and true or false) or false
        -- Scope filtering for test mode
        if test then
            local testScope = _G.MSUF_DispelBorderTestScope or "shared"
            if testScope ~= "shared" then
                local u = self.unit
                if testScope == "party" or testScope == "raid" or testScope == "mythicraid" or testScope == "gf_party" or testScope == "gf_raid" or testScope == "gf_mythicraid" then
                    test = false  -- GF scope: don't show on UF
                elseif u ~= testScope then
                    test = false  -- Different UF: don't show
                end
            end
        end
        local wantDispel = (cfg.dispelOutlineMode == 1) or test
        if wantDispel then
            local u = self.unit
            if u == "player" or u == "target" or u == "focus" or u == "targettarget" then
                dispel = test or (self._msufDispelOutlineOn == true)
            end
        end
    end

    -- Purge state detection.
    local purge = false
    do
        local test = borderTestsActive and (_G.MSUF_PurgeBorderTestMode and true or false) or false
        if test then
            local testScope = _G.MSUF_PurgeBorderTestScope or "shared"
            local u = self.unit
            if testScope == "party" or testScope == "raid" or testScope == "mythicraid" or testScope == "gf_party" or testScope == "gf_raid" or testScope == "gf_mythicraid" then
                test = false
            elseif testScope ~= "shared" and u ~= testScope then
                test = false
            end
        end
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
                local test = borderTestsActive and (_G.MSUF_BossTargetBorderTestMode and true or false) or false
                local wantBossTarget = (cfg.bossTargetOutlineMode == 1) or test
                if wantBossTarget then
                    bossTarget = test or (self._msufBossTargetHLOn == true)
                end
            end
        end
    end

    -- Apply the normal black outline.
    MSUF_ApplyBarOutline(self, baseThickness, self._msufBarOutline)

    -- Resolve highlight priority: Dispel > Aggro > Purge > Boss Target (default), or custom order.
    local hlKey = 0
    if cfg.highlightPrioEnabled and type(cfg.highlightPrioOrder) == "table" then
        for _, kind in ipairs(cfg.highlightPrioOrder) do
            if kind == "dispel" and dispel then hlKey = 2; break
            elseif kind == "aggro" and threat then hlKey = 1; break
            elseif kind == "purge" and purge then hlKey = 3; break
            elseif kind == "bossTarget" and bossTarget then hlKey = 4; break
            end
        end
    else
        hlKey = (dispel and 2) or (threat and 1) or (purge and 3) or (bossTarget and 4) or 0
    end

    -- Resolve color for the active highlight key.
    local hlR, hlG, hlB = 0, 0, 0
    if hlKey == 1 then hlR, hlG, hlB = aggroR, aggroG, aggroB
    elseif hlKey == 2 then hlR, hlG, hlB = dispelR, dispelG, dispelB
    elseif hlKey == 3 then hlR, hlG, hlB = purgeR, purgeG, purgeB
    elseif hlKey == 4 then hlR, hlG, hlB = bossTargetR, bossTargetG, bossTargetB
    end

    -- Apply (or hide) the highlight overlay.
    MSUF_ApplyHighlightOverlay(self, hlKey, hlR, hlG, hlB, cfg)

    local tintBarBorder = (hlKey == 2)
    self._msufBarBorderTintActive = tintBarBorder and true or nil
    self._msufBarBorderTintR = tintBarBorder and hlR or nil
    self._msufBarBorderTintG = tintBarBorder and hlG or nil
    self._msufBarBorderTintB = tintBarBorder and hlB or nil
    _ApplyUFBarBorderTint(self, tintBarBorder, hlR, hlG, hlB)
 end
-- Export with RoundedUF notification (replaces former hooksecurefunc in RoundedUnitframes).
_G.MSUF_RefreshRareBarVisuals = function(frame)
    MSUF_ApplyRareVisuals(frame)
    local fnR = _G.MSUF_RoundedUF_OnRareVisualsRefreshed; if fnR then fnR(frame) end
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
    if type(fn) == "function" and frames then
        if isShared then
            local t = frames.target; if t and t.unit == "target" then fn(t) end
            local f = frames.focus; if f and f.unit == "focus" then fn(f) end
            for i = 1, 5 do local b = frames["boss" .. i]; if b and b.unit == ("boss" .. i) then fn(b) end end
        elseif testScope == "boss" then
            for i = 1, 5 do local b = frames["boss" .. i]; if b and b.unit == ("boss" .. i) then fn(b) end end
        elseif not isGF then
            local uf = frames[testScope]; if uf and uf.unit == testScope then fn(uf) end
        end
    end
    -- Also refresh Group Frames
    local GF = _G.MSUF_NS and _G.MSUF_NS.GF
    if GF and GF._UpdateAggro and GF.frames then
        for gf in pairs(GF.frames) do
            if not active then
                gf._msufGFAggroLevel = nil
                local border = gf._msufGFHighlightBorder
                if border and border:IsShown() and not gf._msufGFDispelType then
                    border._msufHLActivePrio = nil; border:Hide()
                end
            end
            GF._UpdateAggro(gf, gf.unit)
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
    if type(fn) == "function" and frames then
        local ufUnits = isShared and { "player", "target", "focus", "targettarget" } or (not isGF and { testScope } or {})
        for _, u in ipairs(ufUnits) do
            local uf = frames[u]; if uf and uf.unit == u then fn(uf) end
        end
    end
    -- Also force-clear UF glow when turning off
    if not active and frames then
        for _, uf in pairs(frames) do
            if uf then _StopDispelGlow(uf) end
        end
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
                    local borderAnchor = gf._msufGFHighlightBorder
                    if borderAnchor and borderAnchor ~= anchor then _StopDispelGlowOn(borderAnchor) end
                    if gf ~= anchor and gf ~= borderAnchor then _StopDispelGlowOn(gf) end
                end
                local border = gf._msufGFHighlightBorder
                if border and border:IsShown() and not gf._msufGFAggroLevel then
                    border._msufHLActivePrio = nil; border:Hide()
                end
                GF._UpdateDispel(gf, gf.unit)
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
                    s:SetFrameStrata(uf:GetFrameStrata())
                    local baseLevel = uf:GetFrameLevel() + 3
                    if uf.hpBar and uf.hpBar.GetFrameLevel then
                        baseLevel = uf.hpBar:GetFrameLevel() + 3
                    end
                    s:SetFrameLevel(baseLevel)
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
    local function AnyAggroOutlineEnabled()
        if _OutlineModeEnabledForUnit("target", "aggroOutlineMode", "hlAggroEnabled") then return true end
        if _OutlineModeEnabledForUnit("focus", "aggroOutlineMode", "hlAggroEnabled") then return true end
        for i = 1, 5 do
            if _OutlineModeEnabledForUnit("boss" .. i, "aggroOutlineMode", "hlAggroEnabled") then return true end
        end
        return false
    end

    local function RefreshAggroForUnit(u)
        if not u or not MSUF_IsAggroOutlineUnit(u) then return end
        local frames = _G.MSUF_UnitFrames
        local uf = frames and frames[u]
        if not uf or uf.unit ~= u then return end
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
            if UnitThreatSituation then
                local raw = UnitThreatSituation("player", u)
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

    -- UNIT_THREAT_* stay on dedicated frame (EventBus rejects UNIT_* events)
    local ef = F.CreateFrame("Frame")
    ef:SetScript("OnEvent", function(_, event, unit)
        RefreshAggroForUnit(unit)
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
                local function _flushTgt() _qTgt = nil; RefreshAggroForUnit("target") end
                local function _flushFoc() _qFoc = nil; RefreshAggroForUnit("focus") end
                MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_AGGRO_OUTLINE", function()
                    if not _qTgt then _qTgt = true; if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("BORDER_AGGRO_TARGET", _flushTgt) else C_Timer.After(0, _flushTgt) end end
                end)
                MSUF_EventBus_Register("PLAYER_FOCUS_CHANGED", "MSUF_AGGRO_OUTLINE", function()
                    if not _qFoc then _qFoc = true; if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("BORDER_AGGRO_FOCUS", _flushFoc) else C_Timer.After(0, _flushFoc) end end
                end)
            end
        else
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

    local function HasDispellableDebuff(unit)
        local CUA = C_UnitAuras
        local getSlots = CUA and CUA.GetAuraSlots
        local getBySlot = CUA and CUA.GetAuraDataBySlot
        if type(getSlots) ~= "function" then return false end
        local has = false
        local aid, dispelType
        local _, slot = getSlots(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", 1, nil)
        if slot ~= nil then
            has = true
            if type(getBySlot) == "function" then
                local aura = getBySlot(unit, slot)
                if aura then
                    aid = aura.auraInstanceID or aid
                    local dn = aura.dispelName
                    local dnIsSecret = issecretvalue and issecretvalue(dn)
                    if not dnIsSecret and type(dn) == "string" and dn ~= "" and dn ~= "None" and dn ~= "DISPELLABLE" then
                        dispelType = dn
                    end
                end
            end
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
        s:SetFrameStrata(uf:GetFrameStrata())
        local baseLevel = uf:GetFrameLevel() + 3
        if uf.hpBar and uf.hpBar.GetFrameLevel then
            baseLevel = uf.hpBar:GetFrameLevel() + 3
        end
        s:SetFrameLevel(baseLevel)
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
        return true
    end

    local function HideAllPurgeSentinels(uf)
        local pool = uf._msufPurgeSentinels
        if not pool then return end
        for i = 1, #pool do
            pool[i]:SetAlpha(0)
        end
    end

    local function UpdateUnit(unit, forceRefresh)
        local uf = _G.MSUF_UnitFrames and _G.MSUF_UnitFrames[unit]
        if not uf or uf.unit ~= unit then return end

        local cfg = _RefreshBorderSettingsForFrame(uf)
        local dispelEnabled = (cfg.dispelOutlineMode == 1)
        local purgeEnabled  = (cfg.purgeOutlineMode  == 1)

        local dispelOn = false
        -- Dispel = remove debuffs from allies; Purge = steal/remove buffs from enemies.
        -- UnitCanAssist/UnitCanAttack handle duels and PvP correctly (UnitIsFriend
        -- returns true for same-faction duel opponents, which breaks purge detection).
        local canAssist = UnitCanAssist and UnitCanAssist("player", unit)
        local canAttack = UnitCanAttack and UnitCanAttack("player", unit)
        local dispelAid, dispelType
        if dispelEnabled and canAssist and PlayerMayFriendlyDispel() then
            dispelOn, dispelAid, dispelType = HasDispellableDebuff(unit)
        end

        -- Purge: sentinel frames handle rendering via SetAlpha with secret values.
        -- Secret constraints prevent boolean tracking ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â sentinels ARE the border.
        -- Purge participates in highlight priority only via test mode.
        if purgeEnabled and canAttack and unit ~= "player" and PlayerMayPurge() then
            UpdatePurgeSentinels(uf, unit, cfg)
        else
            HideAllPurgeSentinels(uf)
        end

        local changed = false
        if forceRefresh or uf._msufDispelOutlineOn ~= dispelOn or uf._msufDispelAuraID ~= dispelAid or uf._msufDispelType ~= dispelType then
            uf._msufDispelOutlineOn = dispelOn
            uf._msufDispelAuraID = dispelAid
            uf._msufDispelType = dispelType
            changed = true
        end

        if changed then
            if _G.MSUF_RefreshRareBarVisuals then
                _G.MSUF_RefreshRareBarVisuals(uf)
            end
        end
    end

    _G.MSUF_RefreshDispelOutlineStates = function(forceRefresh)
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
    local function ResolveDispelAuraEventWants()
        local friendlyDispel = false
        if PlayerMayFriendlyDispel() then
            friendlyDispel = _OutlineModeEnabledForUnit("player", "dispelOutlineMode", "hlDispelEnabled")
                or _OutlineModeEnabledForUnit("target", "dispelOutlineMode", "hlDispelEnabled")
                or _OutlineModeEnabledForUnit("focus", "dispelOutlineMode", "hlDispelEnabled")
                or _OutlineModeEnabledForUnit("targettarget", "dispelOutlineMode", "hlDispelEnabled")
        end
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
            _dispelAuraQueued[u] = nil
            if u then
                UpdateUnit(u, false)
            end
        end
        _dispelAuraUnitsN = 0
    end
    local function QueueDispelAuraUnit(unit)
        if _dispelAuraQueued[unit] then return end
        _dispelAuraQueued[unit] = true
        _dispelAuraUnitsN = _dispelAuraUnitsN + 1
        _dispelAuraUnits[_dispelAuraUnitsN] = unit
        if not _dispelAuraFlushQueued then
            _dispelAuraFlushQueued = true
            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, FlushDispelAuraUnits)
            else
                FlushDispelAuraUnits()
            end
        end
    end

    local function AuraDataMayAffectFriendlyDispel(aura)
        if type(aura) ~= "table" then return true end

        local dn = aura.dispelName
        if issecretvalue and issecretvalue(dn) then return true end
        if type(dn) == "string" then
            return dn ~= "" and dn ~= "None"
        end

        local harmful = aura.isHarmful
        if issecretvalue and issecretvalue(harmful) then return true end
        if harmful == true then return true end
        if harmful == false then return false end

        return true
    end

    local function UpdateInfoMayAffectFriendlyDispel(unit, updateInfo)
        if type(updateInfo) ~= "table" or updateInfo.isFullUpdate then return true end

        local added = updateInfo.addedAuras
        if added then
            for i = 1, #added do
                if AuraDataMayAffectFriendlyDispel(added[i]) then return true end
            end
        end

        local updated = updateInfo.updatedAuraInstanceIDs
        if updated and #updated > 0 then return true end

        local removed = updateInfo.removedAuraInstanceIDs
        if removed and #removed > 0 then
            local uf = _G.MSUF_UnitFrames and _G.MSUF_UnitFrames[unit]
            return uf and (uf._msufDispelOutlineOn or uf._msufDispelAuraID ~= nil) or false
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
            if _friendlyDispelAuraWant and UnitCanAssist and UnitCanAssist("player", unit) then
                shouldQueue = UpdateInfoMayAffectFriendlyDispel(unit, updateInfo)
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
                    local force = ForceVisualTest()
                    UpdateUnit("target", force)
                    UpdateUnit("targettarget", force)
                end
                local function _flushDFoc()
                    _qDFoc = nil
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
