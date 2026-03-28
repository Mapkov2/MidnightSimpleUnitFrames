-- Core/MSUF_Borders.lua  Aggro / Dispel / Purge border system + UI_SCALE handler
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...

local F = ns.Cache and ns.Cache.F or {}
F.CreateFrame = F.CreateFrame or CreateFrame
local type, tonumber, ipairs, pairs = type, tonumber, ipairs, pairs
local MSUF_TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"

-- From main file (exported to _G)
local MSUF_ForEachUnitFrame = _G.MSUF_ForEachUnitFrame
local MSUF_GetDesiredBarBorderThicknessAndStamp = _G.MSUF_GetDesiredBarBorderThicknessAndStamp
local MSUF_BarBorderCache = _G.MSUF_BarBorderCache
local MSUF_EventBus_Register = _G.MSUF_EventBus_Register
local MSUF_EventBus_Unregister = _G.MSUF_EventBus_Unregister

local _borderCfg = { serial = -1 }
local function _Clamp01(v, def)
    if type(v) ~= "number" then return def end
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end
local function _RefreshBorderSettingsCache()
    local serial = _G.MSUF_UFCORE_SETTINGS_SERIAL or 0
    if _borderCfg.serial == serial then return _borderCfg end
    _borderCfg.serial = serial

    local g = (MSUF_DB and MSUF_DB.general) or nil
    -- Unified hl* keys (Phase 15b) with fallback to legacy keys
    _borderCfg.hlAggroEnabled = (g and g.hlAggroEnabled ~= nil) and g.hlAggroEnabled
        or ((g and g.aggroOutlineMode == 1) and true or false)
    _borderCfg.hlDispelEnabled = (g and g.hlDispelEnabled ~= nil) and g.hlDispelEnabled
        or ((g and g.dispelOutlineMode == 1) and true or false)
    _borderCfg.hlPurgeEnabled = (g and g.hlPurgeEnabled ~= nil) and g.hlPurgeEnabled
        or ((g and g.purgeOutlineMode == 1) and true or false)
    _borderCfg.hlAggroSize = tonumber(g and g.hlAggroSize) or tonumber(g and g.highlightBorderThickness) or 2
    if _borderCfg.hlAggroSize < 1 then _borderCfg.hlAggroSize = 1 end
    _borderCfg.hlAggroOffset = tonumber(g and g.hlAggroOffset) or 0
    _borderCfg.hlAggroLayer  = (g and g.hlAggroLayer) or "DEFAULT"
    _borderCfg.hlAggroMode   = (g and g.hlAggroMode) or "ALL"
    _borderCfg.hlTargetEnabled = (g and g.hlTargetEnabled ~= nil) and g.hlTargetEnabled or false
    _borderCfg.hlTargetSize   = tonumber(g and g.hlTargetSize) or 2
    if _borderCfg.hlTargetSize < 1 then _borderCfg.hlTargetSize = 1 end
    _borderCfg.hlTargetOffset = tonumber(g and g.hlTargetOffset) or 0
    _borderCfg.hlTargetLayer  = (g and g.hlTargetLayer) or "DEFAULT"
    _borderCfg.hlPrioEnabled = (g and g.hlPrioEnabled ~= nil) and g.hlPrioEnabled
        or ((g and g.highlightPrioEnabled == 1) and true or false)
    _borderCfg.hlPrioOrder = (g and type(g.hlPrioOrder) == "table") and g.hlPrioOrder
        or (g and type(g.highlightPrioOrder) == "table") and g.highlightPrioOrder or nil
    -- Legacy compat (kept for backward reads elsewhere)
    _borderCfg.aggroOutlineMode = _borderCfg.hlAggroEnabled and 1 or 0
    _borderCfg.dispelOutlineMode = _borderCfg.hlDispelEnabled and 1 or 0
    _borderCfg.purgeOutlineMode = _borderCfg.hlPurgeEnabled and 1 or 0
    _borderCfg.highlightBorderThickness = _borderCfg.hlAggroSize
    _borderCfg.highlightPrioEnabled = _borderCfg.hlPrioEnabled
    _borderCfg.highlightPrioOrder = _borderCfg.hlPrioOrder
    _borderCfg.aggroR  = _Clamp01(g and (g.hlAggroColorR or g.aggroBorderColorR),  1.00)
    _borderCfg.aggroG  = _Clamp01(g and (g.hlAggroColorG or g.aggroBorderColorG),  0.50)
    _borderCfg.aggroB  = _Clamp01(g and (g.hlAggroColorB or g.aggroBorderColorB),  0.00)
    _borderCfg.dispelR = _Clamp01(g and (g.hlDispelColorR or g.dispelBorderColorR), 0.25)
    _borderCfg.dispelG = _Clamp01(g and (g.hlDispelColorG or g.dispelBorderColorG), 0.75)
    _borderCfg.dispelB = _Clamp01(g and (g.hlDispelColorB or g.dispelBorderColorB), 1.00)
    _borderCfg.purgeR  = _Clamp01(g and (g.hlPurgeColorR or g.purgeBorderColorR),  1.00)
    _borderCfg.purgeG  = _Clamp01(g and (g.hlPurgeColorG or g.purgeBorderColorG),  0.85)
    _borderCfg.purgeB  = _Clamp01(g and (g.hlPurgeColorB or g.purgeBorderColorB),  0.00)
    _borderCfg.hlTargetColorR = _Clamp01(g and g.hlTargetColorR, 1.00)
    _borderCfg.hlTargetColorG = _Clamp01(g and g.hlTargetColorG, 1.00)
    _borderCfg.hlTargetColorB = _Clamp01(g and g.hlTargetColorB, 1.00)
    return _borderCfg
end

local _borderIterState = {}

local function _Iter_SyncBorderStamps(uf)
    if not uf or not uf.unit then return end
    local S = _borderIterState
    uf._msufBarBorderStamp = S.stamp
    uf._msufBarOutlineThickness = S.thickness
    uf._msufBarOutlineEdgeSize = -1
    uf._msufHighlightEdgeSize = -1
    uf._msufHighlightColorKey = -1
    uf._msufHighlightBottomIsPower = nil
    local pb = uf.targetPowerBar
    local pbDetached = uf._msufPowerBarDetached
    uf._msufBarOutlineBottomIsPower = (pb and not pbDetached and pb.IsShown and pb:IsShown()) and true or false
    if S.apply then S.apply(uf) end
end

local function _Iter_ResetBorderOnScale(uf)
    if uf and uf.unit then
        uf._msufBarBorderStamp = nil
        uf._msufBarOutlineEdgeSize = -1
        if type(_G.MSUF_QueueUnitframeVisual) == "function" then
            _G.MSUF_QueueUnitframeVisual(uf)
        end
    end
end

local MSUF_ApplyRareVisuals

-- Per-unit hlOverride resolver. Maps unit IDs to DB keys and checks per-unit overrides.
local function _UnitToDbKey(unit)
    if not unit then return nil end
    if unit:sub(1, 4) == "boss" then return "boss" end
    return unit
end
local function _UnitHlVal(unit, key, cfgVal)
    local dbKey = _UnitToDbKey(unit)
    if not dbKey then return cfgVal end
    local db = MSUF_DB and MSUF_DB[dbKey]
    if type(db) ~= "table" or not db.hlOverride then return cfgVal end
    local v = db[key]
    if v ~= nil then return v end
    return cfgVal
end
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
-- Helper: read an RGB triplet from DB general table with fallback defaults.
-- Eliminates the 3x repeated pattern of g.prefixR / g.prefixG / g.prefixB extraction.
local function _ReadRGB(g, rKey, gKey, bKey, dr, dg, db)
    if not g then return dr, dg, db end
    local r, gg, b = g[rKey], g[gKey], g[bKey]
    if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
        return r, gg, b
    end
    return dr, dg, db
end

-- Sub-function: apply the normal black bar outline.
local function MSUF_ApplyBarOutline(self, thickness, o)
    if thickness <= 0 then
        if o then
            ns.Util.HideKeys(o, ns.Bars._outlineParts, "frame")
        end
        self._msufBarOutlineThickness = 0
        self._msufBarOutlineEdgeSize = 0
        self._msufBarOutlineBottomIsPower = false
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

    -- Detached power bar: apply its own outline frame.
    -- Uses its own thickness setting (detachedPowerBarOutline) so the user
    -- can match class power outline independently from the main frame outline.
    if pb and pbDetached and pb.IsShown and pb:IsShown() then
        local dpbO = self._msufDetachedPBOutline
        if not dpbO then
            local template = (BackdropTemplateMixin and "BackdropTemplate") or nil
            dpbO = F.CreateFrame("Frame", nil, pb, template)
            dpbO:EnableMouse(false)
            dpbO:SetFrameLevel((pb.GetFrameLevel and pb:GetFrameLevel() or 0) + 2)
            self._msufDetachedPBOutline = dpbO
            dpbO._msufLastEdgeSize = -1
        end
        local barsDB = MSUF_DB and MSUF_DB.bars
        local dpbThick = (barsDB and tonumber(barsDB.detachedPowerBarOutline)) or thickness
        if dpbThick < 0 then dpbThick = 0 elseif dpbThick > 6 then dpbThick = 6 end
        if dpbThick <= 0 then
            dpbO:Hide()
        else
            local dpbEdge = (type(snap) == "function") and snap(dpbO, dpbThick) or dpbThick
            if dpbO._msufLastEdgeSize ~= dpbEdge then
                dpbO:SetBackdrop({ edgeFile = MSUF_TEX_WHITE8, edgeSize = dpbEdge })
                dpbO:SetBackdropBorderColor(0, 0, 0, 1)
                dpbO._msufLastEdgeSize = dpbEdge
            end
            dpbO:ClearAllPoints()
            dpbO:SetPoint("TOPLEFT", pb, "TOPLEFT", -dpbEdge, dpbEdge)
            dpbO:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", dpbEdge, -dpbEdge)
            dpbO:Show()
        end
    elseif self._msufDetachedPBOutline then
        self._msufDetachedPBOutline:Hide()
    end
end

-- Sub-function: create/update highlight overlay frame for aggro/dispel/purge.
local function MSUF_ApplyHighlightOverlay(self, hlKey, hlR, hlG, hlB, cfg)
    local hlFrame = self._msufHighlightOutline

    if hlKey == 0 then
        if hlFrame then hlFrame:Hide() end
        self._msufHighlightColorKey = 0
        return
    end

    local hlThickness = (cfg and cfg.hlAggroSize) or (cfg and cfg.highlightBorderThickness) or 2

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

    hlFrame:Show()
end

MSUF_ApplyRareVisuals = function(self)
    if not self or not self.unit then  return end
    if self.border then
        self.border:Hide()
    end
    local baseThickness = 0
    if type(MSUF_GetDesiredBarBorderThicknessAndStamp) == "function" then
        baseThickness = select(1, MSUF_GetDesiredBarBorderThicknessAndStamp())
    end
    baseThickness = tonumber(baseThickness) or 0

    local cfg = _RefreshBorderSettingsCache()
    local unit = self.unit

    -- Per-unit override: resolve enabled/size from unit DB if hlOverride is set
    local aggroEnabled = _UnitHlVal(unit, "hlAggroEnabled", cfg.hlAggroEnabled)
    local dispelEnabled = _UnitHlVal(unit, "hlDispelEnabled", cfg.hlDispelEnabled)
    local purgeEnabled = _UnitHlVal(unit, "hlPurgeEnabled", cfg.hlPurgeEnabled)
    local hlAggroSize = _UnitHlVal(unit, "hlAggroSize", cfg.hlAggroSize)
    local hlPrioEnabled = _UnitHlVal(unit, "hlPrioEnabled", cfg.hlPrioEnabled)

    -- Aggro state detection (target/focus/boss only).
    local wantAggro = MSUF_IsAggroOutlineUnit(unit) and (aggroEnabled or (_G and _G.MSUF_AggroBorderTestMode))
    local threat = false
    if wantAggro then
        local aggroMode = _UnitHlVal(unit, "hlAggroMode", cfg.hlAggroMode) or "ALL"
        if aggroMode ~= "ALL" then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
            if aggroMode == "HEALER_ONLY" and role ~= "HEALER" then wantAggro = false
            elseif aggroMode == "TANK_ONLY" and role ~= "TANK" then wantAggro = false end
        end
    end
    if wantAggro then
        if _G and _G.MSUF_AggroBorderTestMode then
            threat = true
        elseif UnitThreatSituation then
            local raw = UnitThreatSituation("player", unit)
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
    local purgeR, purgeG, purgeB = cfg.purgeR, cfg.purgeG, cfg.purgeB

    -- Dispel state detection.
    local dispel = false
    do
        local test = (_G and _G.MSUF_DispelBorderTestMode) and true or false
        local wantDispel = dispelEnabled or test
        if wantDispel then
            if unit == "player" or unit == "target" or unit == "focus" or unit == "targettarget" then
                dispel = test or (self._msufDispelOutlineOn == true)
                if test then self._msufDispelTypeName = _G.MSUF_DispelBorderTestType or "Magic" end
            end
        end
    end

    -- Purge state detection.
    local purge = false
    do
        local test = (_G and _G.MSUF_PurgeBorderTestMode) and true or false
        local wantPurge = purgeEnabled or test
        if wantPurge then
            if unit == "target" or unit == "focus" or unit == "targettarget" then
                purge = test or (self._msufPurgeOutlineOn == true)
            end
        end
    end

    -- Target highlight detection (NEW Phase 15b).
    local isTarget = false
    local targetEnabled = _UnitHlVal(unit, "hlTargetEnabled", cfg.hlTargetEnabled)
    if targetEnabled and unit then
        isTarget = UnitIsUnit and UnitIsUnit("player", "target") == false
            and UnitIsUnit(unit, "target") == true
    end

    -- Apply the normal black outline.
    MSUF_ApplyBarOutline(self, baseThickness, self._msufBarOutline)

    -- Resolve highlight priority: Dispel > Aggro > Purge (default), or custom order.
    -- TYPE mode: per-type keys (magic/curse/disease/poison) match against dispelTypeName.
    local hlKey = 0
    local hlPrioOrder = _UnitHlVal(unit, "hlPrioOrder", cfg.hlPrioOrder)
    local dispelTypeLower = dispel and self._msufDispelTypeName and self._msufDispelTypeName:lower() or nil
    if hlPrioEnabled and type(hlPrioOrder) == "table" then
        for _, kind in ipairs(hlPrioOrder) do
            if kind == "dispel" and dispel then hlKey = 2; break
            elseif kind == "aggro" and threat then hlKey = 1; break
            elseif kind == "purge" and purge then hlKey = 3; break
            elseif dispel and dispelTypeLower and kind == dispelTypeLower then hlKey = 2; break
            end
        end
    else
        hlKey = (dispel and 2) or (threat and 1) or (purge and 3) or 0
    end

    -- Resolve color for the active highlight key.
    local hlR, hlG, hlB = 0, 0, 0
    if hlKey == 1 then hlR, hlG, hlB = aggroR, aggroG, aggroB
    elseif hlKey == 2 then
        local resolve = _G.MSUF_ResolveDispelColor
        if resolve then hlR, hlG, hlB = resolve(self._msufDispelTypeName)
        else hlR, hlG, hlB = cfg.dispelR or 0.25, cfg.dispelG or 0.75, cfg.dispelB or 1 end
    elseif hlKey == 3 then hlR, hlG, hlB = purgeR, purgeG, purgeB
    end

    -- Apply (or hide) the highlight overlay, with per-unit size override.
    local overrideCfg = cfg
    if hlAggroSize ~= cfg.hlAggroSize then
        overrideCfg = { hlAggroSize = hlAggroSize, highlightBorderThickness = hlAggroSize }
    end
    MSUF_ApplyHighlightOverlay(self, hlKey, hlR, hlG, hlB, overrideCfg)
 end
_G.MSUF_RefreshRareBarVisuals = MSUF_ApplyRareVisuals

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
    end

    local get = MSUF_GetDesiredBarBorderThicknessAndStamp
    local thickness, stamp = 0, 0
    if type(get) == "function" then
        thickness, stamp = get()
    end

    local apply = _G.MSUF_RefreshRareBarVisuals
    _borderIterState.stamp = stamp
    _borderIterState.thickness = thickness
    _borderIterState.apply = apply
    MSUF_ForEachUnitFrame(_Iter_SyncBorderStamps)
end

-- Helper: iterate all GF live + preview frames with a callback(frame, unit)
local function _ForEachGFFrame(callback)
    local GF = _G.MSUF_NS and _G.MSUF_NS.GF
    if not GF then return end
    if GF.frames then
        for gf in pairs(GF.frames) do callback(gf, gf.unit) end
    end
    if GF._previewFrames then
        for _, list in pairs(GF._previewFrames) do
            for i = 1, #list do
                local pf = list[i]
                if pf then callback(pf, pf.unit or pf._msufGFPreviewUnit) end
            end
        end
    end
end

_G.MSUF_SetAggroBorderTestMode = _G.MSUF_SetAggroBorderTestMode or function(active)
    _G.MSUF_AggroBorderTestMode = active and true or false
    local fn = _G.MSUF_RefreshRareBarVisuals
    local frames = _G.MSUF_UnitFrames
    if type(fn) == "function" and frames then
        local t = frames.target
        if t and t.unit == "target" then fn(t) end
        local f = frames.focus
        if f and f.unit == "focus" then fn(f) end
        for i = 1, 5 do
            local b = frames["boss" .. i]
            if b and b.unit == ("boss" .. i) then fn(b) end
        end
    end
    local gfUpd = _G.MSUF_GF_UpdateHighlight
    if type(gfUpd) == "function" then _ForEachGFFrame(gfUpd) end
end

-- Options-only: Test mode to force the dispel border on while the Settings panel is open.
-- This does NOT change the DB or aura filters; it only affects the outline highlight rendering.
_G.MSUF_SetDispelBorderTestMode = _G.MSUF_SetDispelBorderTestMode or function(active)
    _G.MSUF_DispelBorderTestMode = active and true or false
    local fn = _G.MSUF_RefreshRareBarVisuals
    local frames = _G.MSUF_UnitFrames
    if type(fn) == "function" and frames then
        local p = frames.player
        if p and p.unit == "player" then fn(p) end
        local t = frames.target
        if t and t.unit == "target" then fn(t) end
        local f = frames.focus
        if f and f.unit == "focus" then fn(f) end
        local tt = frames.targettarget
        if tt and tt.unit == "targettarget" then fn(tt) end
    end
    local gfUpd = _G.MSUF_GF_UpdateHighlight
    if type(gfUpd) == "function" then _ForEachGFFrame(gfUpd) end
end

-- Options-only: Test mode to force the purge border on while the Settings panel is open.
_G.MSUF_SetPurgeBorderTestMode = _G.MSUF_SetPurgeBorderTestMode or function(active)
    _G.MSUF_PurgeBorderTestMode = active and true or false
    local frames = _G.MSUF_UnitFrames
    if not frames then return end

    local fn = _G.MSUF_RefreshRareBarVisuals
    local units = { "target", "focus", "targettarget" }
    for _, u in ipairs(units) do
        local uf = frames[u]
        if uf and uf.unit == u then
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
                local g = MSUF_DB and MSUF_DB.general
                local hlThickness = tonumber(g and (g.hlAggroSize or g.highlightBorderThickness)) or 2
                if hlThickness < 1 then hlThickness = 1 end
                local snap = _G.MSUF_Snap
                local edge = (type(snap) == "function") and snap(s, hlThickness) or hlThickness
                s:SetBackdrop({ edgeFile = MSUF_TEX_WHITE8, edgeSize = edge })
                local pr, pg, pb = _ReadRGB(g, "hlPurgeColorR", "hlPurgeColorG", "hlPurgeColorB",
                    g and g.purgeBorderColorR or 1.00,
                    g and g.purgeBorderColorG or 0.85,
                    g and g.purgeBorderColorB or 0.00)
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
        end
    end
end


-- Aggro outline event driver (event-only, no OnUpdate)
do
    local function RefreshAggroForUnit(u)
        local g = MSUF_DB and MSUF_DB.general
        if not (g and (g.hlAggroEnabled or g.aggroOutlineMode == 1)) then return end
        if not u or not MSUF_IsAggroOutlineUnit(u) then return end
        local frames = _G and _G.MSUF_UnitFrames
        local uf = frames and frames[u]
        if not uf or uf.unit ~= u then return end
        local fn = _G and _G.MSUF_RefreshRareBarVisuals
        if type(fn) == "function" then fn(uf) end
    end

    -- UNIT_THREAT_* stay on dedicated frame (EventBus rejects UNIT_* events)
    local ef = F.CreateFrame("Frame")
    ef:SetScript("OnEvent", function(_, event, unit)
        RefreshAggroForUnit(unit)
    end)

    local function ApplyAggroOutlineEventRegistration()
        local g = MSUF_DB and MSUF_DB.general
        local want = (g and (g.hlAggroEnabled or g.aggroOutlineMode == 1)) and true or false

        if want then
            if not ef:IsEventRegistered("UNIT_THREAT_SITUATION_UPDATE") then
                ef:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
            end
            if not ef:IsEventRegistered("UNIT_THREAT_LIST_UPDATE") then
                ef:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
            end
            MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_AGGRO_OUTLINE", function()
                RefreshAggroForUnit("target")
            end)
            MSUF_EventBus_Register("PLAYER_FOCUS_CHANGED", "MSUF_AGGRO_OUTLINE", function()
                RefreshAggroForUnit("focus")
            end)
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

    -- Unified dispel color resolution (shared by Main UF + GF via _G.MSUF_ResolveDispelColor)
    -- Mode SINGLE = one color for all dispels, TYPE = per debuff type
    local DISPEL_TYPE_DEFAULTS = {
        Magic   = { 0.20, 0.60, 1.00 },
        Curse   = { 0.60, 0.00, 1.00 },
        Disease = { 0.60, 0.40, 0.00 },
        Poison  = { 0.00, 0.60, 0.00 },
        Bleed   = { 0.80, 0.10, 0.10 },
    }

    local function _ResolveDispelColor(dispelName)
        local g = MSUF_DB and MSUF_DB.general
        local mode = (g and g.hlDispelColorMode) or "SINGLE"
        if mode == "TYPE" and dispelName then
            if g then
                local prefix = "hlDispelType" .. dispelName
                local r = g[prefix .. "R"]
                if r ~= nil then
                    return r, g[prefix .. "G"] or 0, g[prefix .. "B"] or 0
                end
            end
            local def = DISPEL_TYPE_DEFAULTS[dispelName]
            if def then return def[1], def[2], def[3] end
        end
        -- SINGLE mode or unknown type
        if g then
            local r = g.hlDispelColorR or g.dispelBorderColorR
            if r then return r, g.hlDispelColorG or g.dispelBorderColorG or 0.75, g.hlDispelColorB or g.dispelBorderColorB or 1 end
        end
        return 0.25, 0.75, 1.00
    end
    _G.MSUF_ResolveDispelColor = _ResolveDispelColor
    _G.MSUF_DISPEL_TYPE_DEFAULTS = DISPEL_TYPE_DEFAULTS

    local function HasDispellableDebuff(unit)
        local getSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
        local getBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
        if type(getSlots) ~= "function" then return false, nil end
        local _, slot1 = getSlots(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", 1, nil)
        if not slot1 then return false, nil end
        if type(getBySlot) == "function" then
            local data = getBySlot(unit, slot1)
            if data then
                local dn = data.dispelName
                local iss = _G.issecretvalue
                if iss and iss(dn) then return true, nil end
                if dn and dn ~= "" then return true, dn end
                -- Empty dispelName but player-dispellable = Bleed (Evoker Cauterize etc.)
                return true, "Bleed"
            end
        end
        return true, nil
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
    local _bdTable    = { edgeFile = MSUF_TEX_WHITE8, edgeSize = 1 }

    -- Cached purge color ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â refreshed once per UpdatePurgeSentinels call.
    local _purgeR, _purgeG, _purgeB = 1.00, 0.85, 0.00
    local function _RefreshPurgeColor()
        local g = MSUF_DB and MSUF_DB.general
        if g and g.hlPurgeColorR then
            _purgeR = _Clamp01(g.hlPurgeColorR, 1.00)
            _purgeG = _Clamp01(g.hlPurgeColorG, 0.85)
            _purgeB = _Clamp01(g.hlPurgeColorB, 0.00)
        else
            _purgeR, _purgeG, _purgeB = _ReadRGB(g, "purgeBorderColorR", "purgeBorderColorG", "purgeBorderColorB", 1.00, 0.85, 0.00)
        end
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
    local function UpdatePurgeSentinels(uf, unit)
        if type(_getSlots) ~= "function" or type(_getBySlot) ~= "function" then return false end

        _RefreshPurgeColor()

        local g = MSUF_DB and MSUF_DB.general
        local hlThickness = tonumber(g and (g.hlAggroSize or g.highlightBorderThickness)) or 2
        if hlThickness < 1 then hlThickness = 1 end
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

        local g = MSUF_DB and MSUF_DB.general
        local dispelEnabled = g and (g.hlDispelEnabled or g.dispelOutlineMode == 1)
        local purgeEnabled  = g and (g.hlPurgeEnabled or g.purgeOutlineMode == 1)

        local dispelOn = false
        local dispelTypeName = nil
        -- Dispel = remove debuffs from allies; Purge = steal/remove buffs from enemies.
        -- UnitCanAssist/UnitCanAttack handle duels and PvP correctly (UnitIsFriend
        -- returns true for same-faction duel opponents, which breaks purge detection).
        local canAssist = UnitCanAssist and UnitCanAssist("player", unit)
        local canAttack = UnitCanAttack and UnitCanAttack("player", unit)
        if dispelEnabled and canAssist then
            dispelOn, dispelTypeName = HasDispellableDebuff(unit)
        end

        -- Purge: sentinel frames handle rendering via SetAlpha with secret values.
        -- Secret constraints prevent boolean tracking ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â sentinels ARE the border.
        -- Purge participates in highlight priority only via test mode.
        if purgeEnabled and canAttack and unit ~= "player" then
            UpdatePurgeSentinels(uf, unit)
        else
            HideAllPurgeSentinels(uf)
        end

        local changed = false
        if forceRefresh or uf._msufDispelOutlineOn ~= dispelOn or uf._msufDispelTypeName ~= dispelTypeName then
            uf._msufDispelOutlineOn = dispelOn
            uf._msufDispelTypeName = dispelTypeName
            changed = true
        end

        if changed then
            if type(_G.MSUF_RefreshRareBarVisuals) == "function" then
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

    f:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" then
            if unit ~= "player" and unit ~= "target" and unit ~= "focus" and unit ~= "targettarget" then return end
            local g = MSUF_DB and MSUF_DB.general
            if not (g and (g.hlDispelEnabled or g.dispelOutlineMode == 1 or g.hlPurgeEnabled or g.purgeOutlineMode == 1)) then return end
            UpdateUnit(unit, false)
            return
        end

        -- Init / safety clear so state is correct without requiring Edit Mode / manual refresh.
        if event == "PLAYER_ENTERING_WORLD" then
            _G.MSUF_RefreshDispelOutlineStates(true)
            return
        end
    end)

    local function ApplyDispelOutlineEventRegistration()
        local g = MSUF_DB and MSUF_DB.general
        local want = (g and (g.hlDispelEnabled or g.dispelOutlineMode == 1 or g.hlPurgeEnabled or g.purgeOutlineMode == 1)) and true or false

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
            MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_DISPEL_OUTLINE", function()
                UpdateUnit("target", true)
                UpdateUnit("targettarget", true)
            end)
            MSUF_EventBus_Register("PLAYER_FOCUS_CHANGED", "MSUF_DISPEL_OUTLINE", function()
                UpdateUnit("focus", true)
            end)
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
        if type(_G.MSUF_UpdatePixelPerfect) == "function" then
            _G.MSUF_UpdatePixelPerfect()
    end
        if MSUF_BarBorderCache then
            MSUF_BarBorderCache.stamp = nil
    end
        MSUF_ForEachUnitFrame(_Iter_ResetBorderOnScale)
_G.MSUF_UpdateCastbarVisuals()
     end)
end
