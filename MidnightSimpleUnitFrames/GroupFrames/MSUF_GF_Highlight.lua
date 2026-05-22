-- MSUF_GF_Highlight.lua - Group frame highlight config, borders, and target indicators
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local UnitIsUnit = _G.UnitIsUnit
local issecretvalue = _G.issecretvalue
local math_max = math.max

local function _UnsecretBool(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value and true or false
end
------------------------------------------------------------------------
-- Highlight value resolver: Bars hl* keys Ã¢â€ â€™ old GF conf key fallback
-- Bars system uses hlAggroEnabled/aggroOutlineMode, hlAggroColorR, etc.
-- Old GF DB uses aggroEnabled, aggroR, etc.
-- Single-pass resolution: conf.hlOverride Ã¢â€ â€™ general Ã¢â€ â€™ conf[fallback]
------------------------------------------------------------------------
local _HL_FALLBACK = {
    hlAggroEnabled  = "aggroEnabled",
    hlAggroColorR   = "aggroR",
    hlAggroColorG   = "aggroG",
    hlAggroColorB   = "aggroB",
    hlAggroMode     = "aggroMode",
    hlDispelEnabled = "dispelEnabled",
    hlTargetEnabled = "targetIndicator",
    hlTargetColorR  = "targetR",
    hlTargetColorG  = "targetG",
    hlTargetColorB  = "targetB",
}

local _HL_OUTLINE_MODE = {
    hlAggroEnabled  = "aggroOutlineMode",
    hlDispelEnabled = "dispelOutlineMode",
}

local function OutlineModeToEnabled(mode)
    if mode == nil then return nil end
    if mode == true or mode == false then return mode end
    local n = tonumber(mode)
    if n ~= nil then return n == 1 end
    return nil
end

local function HLVal(kind, key)
    local conf = GF.GetConf(kind)
    -- Priority 1: GF-local override
    local modeKey = _HL_OUTLINE_MODE[key]
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if modeKey then
        if conf.hlOverride then
            local enabled = OutlineModeToEnabled(conf[modeKey])
            if enabled ~= nil then return enabled end
            if conf[key] ~= nil then
                enabled = OutlineModeToEnabled(conf[key])
                if enabled ~= nil then return enabled end
                return conf[key]
            end
        end
        if gen then
            local enabled = OutlineModeToEnabled(gen[modeKey])
            if enabled ~= nil then return enabled end
            if gen[key] ~= nil then
                enabled = OutlineModeToEnabled(gen[key])
                if enabled ~= nil then return enabled end
                return gen[key]
            end
        end
    elseif conf.hlOverride then
        if conf[key] ~= nil then return conf[key] end
    end
    if not modeKey and gen then
        if gen[key] ~= nil then return gen[key] end
    end
    -- Priority 3: legacy GF conf fallback
    local fb = _HL_FALLBACK[key]
    if fb and conf[fb] ~= nil then
        if modeKey then
            local enabled = OutlineModeToEnabled(conf[fb])
            if enabled ~= nil then return enabled end
        end
        return conf[fb]
    end
    return nil
end

local function HLValCached(conf, gen, key)
    local modeKey = _HL_OUTLINE_MODE[key]
    if modeKey then
        if conf.hlOverride then
            local enabled = OutlineModeToEnabled(conf[modeKey])
            if enabled ~= nil then return enabled end
            if conf[key] ~= nil then
                enabled = OutlineModeToEnabled(conf[key])
                if enabled ~= nil then return enabled end
                return conf[key]
            end
        end
        if gen then
            local enabled = OutlineModeToEnabled(gen[modeKey])
            if enabled ~= nil then return enabled end
            if gen[key] ~= nil then
                enabled = OutlineModeToEnabled(gen[key])
                if enabled ~= nil then return enabled end
                return gen[key]
            end
        end
    elseif conf.hlOverride then
        if conf[key] ~= nil then return conf[key] end
    end
    if not modeKey and gen then
        if gen[key] ~= nil then return gen[key] end
    end
    local fb = _HL_FALLBACK[key]
    if fb and conf[fb] ~= nil then
        if modeKey then
            local enabled = OutlineModeToEnabled(conf[fb])
            if enabled ~= nil then return enabled end
        end
        return conf[fb]
    end
    return nil
end

local function HLPrioEnabledCached(conf, gen)
    local value
    if conf and conf.hlOverride then
        value = conf.hlPrioEnabled
        if value == nil then value = conf.highlightPrioEnabled end
    end
    if value == nil and gen then
        value = gen.hlPrioEnabled
        if value == nil then value = gen.highlightPrioEnabled end
    end
    return value == true or value == 1
end

local function HLPrioLocalValue(conf)
    if not (conf and conf.hlOverride) then return nil end
    local value = conf.hlPrioEnabled
    if value == nil then value = conf.highlightPrioEnabled end
    return value
end

local function HLPrioOrderFrom(scope)
    if type(scope) ~= "table" then return nil end
    if type(scope.hlPrioOrder) == "table" then return scope.hlPrioOrder end
    if type(scope.highlightPrioOrder) == "table" then return scope.highlightPrioOrder end
    return nil
end

local function HLPrioOrderCached(conf, gen)
    if HLPrioLocalValue(conf) ~= nil then
        return HLPrioOrderFrom(conf) or HLPrioOrderFrom(gen)
    end
    return HLPrioOrderFrom(gen) or HLPrioOrderFrom(conf)
end

GF.NormalizeDispelBorderTrigger = GF.NormalizeDispelBorderTrigger or function(value)
    local fn = _G.MSUF_NormalizeDispelBorderTrigger
    if type(fn) == "function" then return fn(value) end
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "TYPED" or value == "ANY_DISPEL_TYPE" then
        return "DISPEL_TYPE"
    end
    if value == "ANY_DEBUFF" or value == "ANY" or value == "ALL" or value == "ALL_DEBUFFS" then
        return "ANY_DEBUFF"
    end
    return "BY_ME"
end

GF.DispelBorderTriggerNeedsPlayerDispel = GF.DispelBorderTriggerNeedsPlayerDispel or function(value)
    local fn = _G.MSUF_DispelBorderTriggerNeedsPlayerDispel
    if type(fn) == "function" then return fn(value) end
    return GF.NormalizeDispelBorderTrigger(value) == "BY_ME"
end

GF.DispelScanActive = GF.DispelScanActive or function(c)
    return c and c.dispelScanActive == true
end

 -- Aggro border (secret-safe UnitThreatSituation)
------------------------------------------------------------------------
local _hlBdInsets = { left = 0, right = 0, top = 0, bottom = 0 }
local function _applyHighlightBorderStyle(border, conf, edgeSz, ofs, texKey, layer, r, g, b, a)
    edgeSz = math_max(1, edgeSz or 2)
    ofs = tonumber(ofs) or 0
    local edgeFile = GF.ResolveHighlightTexture(texKey)

    -- IMPORTANT:
    -- GF highlight live-apply must materialize a NEW backdrop description when
    -- edge texture/size changes. Reusing one shared table can leave existing
    -- Backdrop frames visually stale even though our Lua-side cache changed.
    -- UF does not have this issue because it creates a fresh literal table.
    if border._msufHLEdge ~= edgeFile or border._msufHLEdgeSz ~= edgeSz then
        border._msufHLEdge   = edgeFile
        border._msufHLEdgeSz = edgeSz
        border:SetBackdrop({ edgeFile = edgeFile, edgeSize = edgeSz, insets = _hlBdInsets })
        border:SetBackdropColor(0, 0, 0, 0)
    end
    r, g, b, a = r or 1, g or 1, b or 1, a or 1
    border._msufHLR, border._msufHLG, border._msufHLB, border._msufHLA = r, g, b, a
    border:SetBackdropBorderColor(r, g, b, a)

    -- Diff-gate anchor offset
    if border._msufHLOfs ~= ofs then
        border._msufHLOfs = ofs
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", -ofs, ofs)
        border:SetPoint("BOTTOMRIGHT", ofs, -ofs)
    end

    -- Layer: visual priority is fixed by frame level; the option only keeps
    -- compatibility with older saved values.
    local anchor = border:GetParent()
    if anchor then
        local owner = anchor:GetParent() or anchor
        local base = owner and owner.health or anchor
        local offset = border._msufHLLayerOffset or GF.LAYER_HIGHLIGHT_BORDER or ((layer == "ABOVE_BORDER") and 8 or 3)
        local wantLvl = GF.SyncFrameLayerAbove and GF.SyncFrameLayerAbove(border, base, offset)
            or ((base.GetFrameLevel and base:GetFrameLevel() or anchor:GetFrameLevel()) + offset)
        if border._msufHLLvl ~= wantLvl then
            border._msufHLLvl = wantLvl
            if not GF.SyncFrameLayerAbove then border:SetFrameLevel(wantLvl) end
        end
    end
end

local function _NotifyRoundedGFHighlight(border)
    if _G.MSUF_RoundedUF_Active ~= true then return end
    local fn = _G.MSUF_RoundedUF_OnGroupHighlightChanged
    if type(fn) == "function" then fn(border) end
end
GF.HighlightValue = HLVal
GF.HighlightValueCached = HLValCached
GF.ApplyHighlightBorderStyle = _applyHighlightBorderStyle
GF.NotifyRoundedHighlight = _NotifyRoundedGFHighlight

------------------------------------------------------------------------
-- HLColor: read highlight COLORS always from MSUF_DB.general first
-- (same source as main UF Ã¢â‚¬â€ Colors panel writes there).
-- hlOverride only gates geometry (size/offset/layer) and enable flags,
-- NOT colors Ã¢â‚¬â€ prevents stale-seeded color copies in gf_party/gf_raid.
------------------------------------------------------------------------
local function HLColor(key, fallback)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    return fallback
end

local function HLColorCached(gen, key, fallback)
    if gen and gen[key] ~= nil then return gen[key] end
    return fallback
end

 ------------------------------------------------------------------------
-- Lightweight border activation (NO SetBackdrop â€” color + show/hide only)
-- PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED entrypoint.
-- Runtime delegates to AuraEffects multi-layer refresh when available;
-- the single-border path below remains as an early-load fallback.
------------------------------------------------------------------------
local function _GF_QuickBorderUpdate(f)
    if not f then return end
    local refresh = GF.RefreshBorder or _G.MSUF_GF_RefreshBorder
    if type(refresh) == "function" then return refresh(f, f.unit) end

    local border = f._msufGFHighlightBorder
    if not border then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end

    -- Dispel/Aggro are always higher priority than Target/Focus.
    -- If either is active, skip target/focus update (full _GF_RefreshBorder handles their order).
    if f._msufGFDispelType and c.dispelEn then return end
    if f._msufGFAggroLevel and f._msufGFAggroLevel >= 1 and c.aggroEn then return end

    -- Priority 3: Target
    if f._msufGFIsTarget and c.targetEn then
        if border._msufHLActivePrio ~= 3 then
            border._msufHLActivePrio = 3
            _applyHighlightBorderStyle(border, nil,
                c.tgtSize or 2,
                c.tgtOfs or 0,
                c.tgtTex,
                c.tgtLayer or "DEFAULT",
                c.tgtR, c.tgtG, c.tgtB, 1)
        else
            border._msufHLR, border._msufHLG, border._msufHLB, border._msufHLA = c.tgtR, c.tgtG, c.tgtB, 1
            border:SetBackdropBorderColor(c.tgtR, c.tgtG, c.tgtB, 1)
        end
        if not border:IsShown() then border:Show() end
        _NotifyRoundedGFHighlight(border)
        return
    end

    -- Priority 4: Focus
    if f._msufGFIsFocus and c.focusEn then
        if border._msufHLActivePrio ~= 4 then
            border._msufHLActivePrio = 4
            _applyHighlightBorderStyle(border, nil,
                c.focSize or 2,
                c.focOfs or 0,
                c.focTex,
                c.focLayer or "DEFAULT",
                c.focR, c.focG, c.focB, 1)
        else
            border._msufHLR, border._msufHLG, border._msufHLB, border._msufHLA = c.focR, c.focG, c.focB, 1
            border:SetBackdropBorderColor(c.focR, c.focG, c.focB, 1)
        end
        if not border:IsShown() then border:Show() end
        _NotifyRoundedGFHighlight(border)
        return
    end

    -- Nothing active
    border._msufHLActivePrio = nil
    _NotifyRoundedGFHighlight(border)
    if border:IsShown() then border:Hide() end
end

 -- Target indicator border
------------------------------------------------------------------------
local function UpdateTargetIndicator(f, unit)
    local border = f._msufGFTargetBorder
    if not border then return end
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end

    if not (c and c.targetEn) or not unit then
        border:Hide()
        return
    end

    local isTarget = UnitIsUnit and _UnsecretBool(UnitIsUnit(unit, "target")) == true
    if isTarget then
        _applyHighlightBorderStyle(border, nil,
            c.tgtSize or 2,
            c.tgtOfs or 0,
            c.tgtTex,
            c.tgtLayer or "DEFAULT",
            c.tgtR or 1,
            c.tgtG or 1,
            c.tgtB or 1, 1)
        border:Show()
    else
        border:Hide()
    end
end


GF.QuickBorderUpdate = _GF_QuickBorderUpdate
GF.UpdateTargetIndicator = UpdateTargetIndicator
_G.MSUF_GF_QuickBorderUpdate = _GF_QuickBorderUpdate
_G.MSUF_GF_UpdateTarget = UpdateTargetIndicator
_G.MSUF_GF_ApplyHLBorderStyle = _applyHighlightBorderStyle
