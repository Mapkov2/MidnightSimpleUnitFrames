-- Core/MSUF_Borders.lua  Aggro / Dispel / Purge border system + UI_SCALE handler
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...

local F = ns.Cache and ns.Cache.F or {}
local type, tonumber, ipairs, pairs = type, tonumber, ipairs, pairs
local MSUF_TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"

-- From main file (exported to _G)
local MSUF_ForEachUnitFrame = _G.MSUF_ForEachUnitFrame
local MSUF_GetDesiredBarBorderThicknessAndStamp = _G.MSUF_GetDesiredBarBorderThicknessAndStamp
local MSUF_BarBorderCache = _G.MSUF_BarBorderCache
local MSUF_EventBus_Register = _G.MSUF_EventBus_Register

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
    uf._msufBarOutlineBottomIsPower = (pb and pb.IsShown and pb:IsShown()) and true or false
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
    local pbWanted = (pb ~= nil) and (self._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
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
end

-- Sub-function: create/update highlight overlay frame for aggro/dispel/purge.
local function MSUF_ApplyHighlightOverlay(self, hlKey, hlR, hlG, hlB, g)
    local hlFrame = self._msufHighlightOutline

    if hlKey == 0 then
        if hlFrame then hlFrame:Hide() end
        self._msufHighlightColorKey = 0
        return
    end

    local hlThickness = (g and g.highlightBorderThickness) or 2
    hlThickness = tonumber(hlThickness) or 2
    if hlThickness < 1 then hlThickness = 1 end

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
    local pbWanted = (pb ~= nil) and (self._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
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

    -- Read DB settings once for the entire function.
    local g = (MSUF_DB and MSUF_DB.general) or nil

    -- Aggro state detection (target/focus/boss only).
    local aggroMode = g and g.aggroOutlineMode or 0
    local wantAggro = MSUF_IsAggroOutlineUnit(self.unit) and ((aggroMode == 1) or (_G and _G.MSUF_AggroBorderTestMode))
    local threat = false
    if wantAggro then
        if _G and _G.MSUF_AggroBorderTestMode then
            threat = true
        elseif UnitThreatSituation then
            threat = (UnitThreatSituation("player", self.unit) == 3)
        end
    end

    -- Read border colors from DB (deduplicated via _ReadRGB).
    local aggroR,  aggroG,  aggroB  = _ReadRGB(g, "aggroBorderColorR",  "aggroBorderColorG",  "aggroBorderColorB",  1.00, 0.50, 0.00)
    local dispelR, dispelG, dispelB = _ReadRGB(g, "dispelBorderColorR", "dispelBorderColorG", "dispelBorderColorB", 0.25, 0.75, 1.00)
    local purgeR,  purgeG,  purgeB  = _ReadRGB(g, "purgeBorderColorR",  "purgeBorderColorG",  "purgeBorderColorB",  1.00, 0.85, 0.00)

    -- Dispel state detection.
    local dispel = false
    do
        local dispelMode = g and g.dispelOutlineMode or 0
        local test = (_G and _G.MSUF_DispelBorderTestMode) and true or false
        local wantDispel = (dispelMode == 1) or test
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
        local purgeMode = g and g.purgeOutlineMode or 0
        local test = (_G and _G.MSUF_PurgeBorderTestMode) and true or false
        local wantPurge = (purgeMode == 1) or test
        if wantPurge then
            local u = self.unit
            if u == "target" or u == "focus" or u == "targettarget" then
                purge = test or (self._msufPurgeOutlineOn == true)
            end
        end
    end

    -- Apply the normal black outline.
    MSUF_ApplyBarOutline(self, baseThickness, self._msufBarOutline)

    -- Resolve highlight priority: Dispel > Aggro > Purge (default), or custom order.
    local hlKey = 0
    if g and g.highlightPrioEnabled == 1 and type(g.highlightPrioOrder) == "table" then
        for _, kind in ipairs(g.highlightPrioOrder) do
            if kind == "dispel" and dispel then hlKey = 2; break
            elseif kind == "aggro" and threat then hlKey = 1; break
            elseif kind == "purge" and purge then hlKey = 3; break
            end
        end
    else
        hlKey = (dispel and 2) or (threat and 1) or (purge and 3) or 0
    end

    -- Resolve color for the active highlight key.
    local hlR, hlG, hlB = 0, 0, 0
    if hlKey == 1 then hlR, hlG, hlB = aggroR, aggroG, aggroB
    elseif hlKey == 2 then hlR, hlG, hlB = dispelR, dispelG, dispelB
    elseif hlKey == 3 then hlR, hlG, hlB = purgeR, purgeG, purgeB
    end

    -- Apply (or hide) the highlight overlay.
    MSUF_ApplyHighlightOverlay(self, hlKey, hlR, hlG, hlB, g)
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

_G.MSUF_SetAggroBorderTestMode = _G.MSUF_SetAggroBorderTestMode or function(active)
    _G.MSUF_AggroBorderTestMode = active and true or false
    local fn = _G.MSUF_RefreshRareBarVisuals
    local frames = _G.MSUF_UnitFrames
    if type(fn) ~= "function" or not frames then return end
    local t = frames.target
    if t and t.unit == "target" then fn(t) end
    local f = frames.focus
    if f and f.unit == "focus" then fn(f) end
    for i = 1, 5 do
        local b = frames["boss" .. i]
        if b and b.unit == ("boss" .. i) then fn(b) end
    end
end

-- Options-only: Test mode to force the dispel border on while the Settings panel is open.
-- This does NOT change the DB or aura filters; it only affects the outline highlight rendering.
_G.MSUF_SetDispelBorderTestMode = _G.MSUF_SetDispelBorderTestMode or function(active)
    _G.MSUF_DispelBorderTestMode = active and true or false
    local fn = _G.MSUF_RefreshRareBarVisuals
    local frames = _G.MSUF_UnitFrames
    if type(fn) ~= "function" or not frames then return end

    local p = frames.player
    if p and p.unit == "player" then fn(p) end
    local t = frames.target
    if t and t.unit == "target" then fn(t) end
    local f = frames.focus
    if f and f.unit == "focus" then fn(f) end
    local tt = frames.targettarget
    if tt and tt.unit == "targettarget" then fn(tt) end
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
                local hlThickness = (g and g.highlightBorderThickness) or 2
                hlThickness = tonumber(hlThickness) or 2
                if hlThickness < 1 then hlThickness = 1 end
                local snap = _G.MSUF_Snap
                local edge = (type(snap) == "function") and snap(s, hlThickness) or hlThickness
                s:SetBackdrop({ edgeFile = MSUF_TEX_WHITE8, edgeSize = edge })
                local pr, pg, pb = _ReadRGB(g, "purgeBorderColorR", "purgeBorderColorG", "purgeBorderColorB", 1.00, 0.85, 0.00)
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
        if not (g and g.aggroOutlineMode == 1) then return end
        if not u or not MSUF_IsAggroOutlineUnit(u) then return end
        local frames = _G and _G.MSUF_UnitFrames
        local uf = frames and frames[u]
        if not uf or uf.unit ~= u then return end
        local fn = _G and _G.MSUF_RefreshRareBarVisuals
        if type(fn) == "function" then fn(uf) end
    end

    -- UNIT_THREAT_* stay on dedicated frame (EventBus rejects UNIT_* events)
    local ef = F.CreateFrame("Frame")
    ef:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    ef:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    ef:SetScript("OnEvent", function(_, event, unit)
        RefreshAggroForUnit(unit)
    end)

    -- Phase 1: TARGET/FOCUS via EventBus
    MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_AGGRO_OUTLINE", function()
        RefreshAggroForUnit("target")
    end)
    MSUF_EventBus_Register("PLAYER_FOCUS_CHANGED", "MSUF_AGGRO_OUTLINE", function()
        RefreshAggroForUnit("focus")
    end)
end


-- Dispel / Purge border event driver: refresh the rare outline when dispellable debuffs
-- or purgeable buffs appear/disappear.
-- Dispel: HARMFUL|RAID_PLAYER_DISPELLABLE (O(1) filter, covers defensive cleanse).
-- Purge:  scans HELPFUL auras for isStealable (RAID_PLAYER_DISPELLABLE doesn't cover
--         Spellsteal / offensive purge in all patches).  Event-driven only, no OnUpdate.
-- Dispel (friendly debuffs) and Purge (enemy buffs) tracked independently.
do
    local f = F.CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")

    if f.RegisterUnitEvent then
        f:RegisterUnitEvent("UNIT_AURA", "player", "target", "focus", "targettarget")
    else
        f:RegisterEvent("UNIT_AURA")
    end

    local function HasDispellableDebuff(unit)
        local getSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
        if type(getSlots) ~= "function" then return false end
        local _, slot1 = getSlots(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", 1, nil)
        return slot1 ~= nil
    end

    -- Purge/Spellsteal detection (combat-safe for 12.0).
    -- Secret booleans can't be compared or branched on, but visual APIs (SetAlpha,
    -- SetBackdropBorderColor) accept secret values directly.  We use "sentinel frames"
    -- Ã¢â‚¬â€ one per HELPFUL aura slot, all positioned identically over the unit frame border.
    -- Each sentinel's alpha is set from isStealable via EvaluateColorFromBoolean.
    -- The returned color has SECRET RGBA Ã¢â‚¬â€ we pass color.a straight to SetAlpha()
    -- (a visual API) so we never compare the secret value.  If ANY sentinel has
    -- alpha=1, the purge border is visually rendered (frame compositing = OR logic).
    local _colorTrue  = CreateColor and CreateColor(1, 1, 1, 1)
    local _colorFalse = CreateColor and CreateColor(0, 0, 0, 0)
    local _evalBool   = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean
    local _getSlots   = C_UnitAuras and C_UnitAuras.GetAuraSlots
    local _getBySlot  = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
    local _bdTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
    local _bdTable    = { edgeFile = MSUF_TEX_WHITE8, edgeSize = 0 }

    -- Cached purge color Ã¢â‚¬â€ refreshed once per UpdatePurgeSentinels call.
    local _purgeR, _purgeG, _purgeB = 1.00, 0.85, 0.00
    local function _RefreshPurgeColor()
        local g = MSUF_DB and MSUF_DB.general
        _purgeR, _purgeG, _purgeB = _ReadRGB(g, "purgeBorderColorR", "purgeBorderColorG", "purgeBorderColorB", 1.00, 0.85, 0.00)
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
        if s._msufEdge == edge then return end
        _bdTable.edgeSize = edge
        s:SetBackdrop(_bdTable)
        s:SetBackdropBorderColor(_purgeR, _purgeG, _purgeB, 1)
        s:ClearAllPoints()
        local hb = uf.hpBar
        local pb = uf.targetPowerBar
        local pbWanted = (pb ~= nil) and (uf._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
        local bottomBar = pbWanted and pb or hb
        if hb then s:SetPoint("TOPLEFT", hb, "TOPLEFT", -edge, edge) end
        if bottomBar then s:SetPoint("BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", edge, -edge) end
        s._msufEdge = edge
        s:Show()
    end

    -- Single-pass: scan HELPFUL slots and set sentinel alphas inline.
    -- No intermediate allSlots table Ã¢â‚¬â€ process each batch directly.
    local _purgeScratch = {}
    local function UpdatePurgeSentinels(uf, unit)
        if type(_getSlots) ~= "function" or type(_getBySlot) ~= "function" then return false end

        _RefreshPurgeColor()

        local g = MSUF_DB and MSUF_DB.general
        local hlThickness = (g and g.highlightBorderThickness) or 2
        hlThickness = tonumber(hlThickness) or 2
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
        local dispelEnabled = (g and g.dispelOutlineMode == 1)
        local purgeEnabled  = (g and g.purgeOutlineMode  == 1)

        local dispelOn = false
        -- Dispel = remove debuffs from allies; Purge = steal/remove buffs from enemies.
        -- UnitCanAssist/UnitCanAttack handle duels and PvP correctly (UnitIsFriend
        -- returns true for same-faction duel opponents, which breaks purge detection).
        local canAssist = UnitCanAssist and UnitCanAssist("player", unit)
        local canAttack = UnitCanAttack and UnitCanAttack("player", unit)
        if dispelEnabled and canAssist then
            dispelOn = HasDispellableDebuff(unit)
        end

        -- Purge: sentinel frames handle rendering via SetAlpha with secret values.
        -- Secret constraints prevent boolean tracking Ã¢â‚¬â€ sentinels ARE the border.
        -- Purge participates in highlight priority only via test mode.
        if purgeEnabled and canAttack and unit ~= "player" then
            UpdatePurgeSentinels(uf, unit)
        else
            HideAllPurgeSentinels(uf)
        end

        local changed = false
        if forceRefresh or uf._msufDispelOutlineOn ~= dispelOn then
            uf._msufDispelOutlineOn = dispelOn
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
            if not (g and (g.dispelOutlineMode == 1 or g.purgeOutlineMode == 1)) then return end
            UpdateUnit(unit, false)
            return
        end

        -- Init / safety clear so state is correct without requiring Edit Mode / manual refresh.
        if event == "PLAYER_ENTERING_WORLD" then
            _G.MSUF_RefreshDispelOutlineStates(true)
            return
        end
    end)

    -- Phase 1: TARGET/FOCUS via EventBus
    MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_DISPEL_OUTLINE", function()
        UpdateUnit("target", true)
        UpdateUnit("targettarget", true)
    end)
    MSUF_EventBus_Register("PLAYER_FOCUS_CHANGED", "MSUF_DISPEL_OUTLINE", function()
        UpdateUnit("focus", true)
    end)
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
