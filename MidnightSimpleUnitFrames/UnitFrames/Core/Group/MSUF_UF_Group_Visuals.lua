local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.RegisterElement) then return end

local AuraCache = GF.AuraCache or {}
local SetShown = AuraCache.SetShown or function(region, show) if region then region:SetShown(show) end end
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitHealthPercent = UnitHealthPercent
local UnitIsUnit = UnitIsUnit
local tonumber = tonumber
local min = math.min
local max = math.max
local floor = math.floor
local next = next

local EMPTY_EVENTS = {}
local VISUAL_HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local VISUAL_AURA_EVENTS = { "UNIT_AURA" }
local VISUAL_HEALTH_AURA_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA" }
local VISUAL_TARGET_EVENT = { "PLAYER_TARGET_CHANGED" }
local VISUAL_FOCUS_EVENT = { "PLAYER_FOCUS_CHANGED" }
local VISUAL_TARGET_FOCUS_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED" }

local function GroupSpec(frame)
    local spec = frame and frame.MSUFSpec
    return spec and spec.group
end

local function EnsureTexture(frame, key, layer)
    local tex = frame[key]
    if not tex then
        tex = frame:CreateTexture(nil, layer or "OVERLAY")
        frame[key] = tex
    end
    return tex
end

local function LayoutTargetEdge(parent, edge, key, size)
    edge:ClearAllPoints()
    if key == "top" then
        edge:SetPoint("TOPLEFT", parent, "TOPLEFT", -size, size)
        edge:SetPoint("TOPRIGHT", parent, "TOPRIGHT", size, size)
        edge:SetHeight(size)
    elseif key == "bottom" then
        edge:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -size, -size)
        edge:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", size, -size)
        edge:SetHeight(size)
    elseif key == "left" then
        edge:SetPoint("TOPLEFT", parent, "TOPLEFT", -size, size)
        edge:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -size, -size)
        edge:SetWidth(size)
    else
        edge:SetPoint("TOPRIGHT", parent, "TOPRIGHT", size, size)
        edge:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", size, -size)
        edge:SetWidth(size)
    end
end

local function UpdateTarget(frame, cfg)
    local show = false
    if cfg.targetIndicator == true and UnitIsUnit and frame.unit then
        local same = UnitIsUnit(frame.unit, "target")
        show = same == true or same == 1
    end
    if not show then
        if frame.MSUFGFTargetEdges then
            for _, edge in pairs(frame.MSUFGFTargetEdges) do SetShown(edge, false) end
        end
        return
    end
    frame.MSUFGFTargetEdges = frame.MSUFGFTargetEdges or {}
    local keys = { "top", "bottom", "left", "right" }
    for i = 1, #keys do
        local key = keys[i]
        local edge = frame.MSUFGFTargetEdges[key]
        if not edge then
            edge = frame:CreateTexture(nil, "OVERLAY", nil, 7)
            frame.MSUFGFTargetEdges[key] = edge
        end
        LayoutTargetEdge(frame, edge, key, 2)
        edge:SetColorTexture(cfg.targetR or 1, cfg.targetG or 1, cfg.targetB or 1, 1)
        SetShown(edge, true)
    end
end

local function UpdateFocus(frame, cfg)
    local show = false
    if cfg.focusIndicator == true and UnitIsUnit and frame.unit then
        local same = UnitIsUnit(frame.unit, "focus")
        show = same == true or same == 1
    end
    if not show then
        if frame.MSUFGFFocusEdges then
            for _, edge in pairs(frame.MSUFGFFocusEdges) do SetShown(edge, false) end
        end
        return
    end
    frame.MSUFGFFocusEdges = frame.MSUFGFFocusEdges or {}
    local keys = { "top", "bottom", "left", "right" }
    local size = max(1, floor((tonumber(cfg.focusSize) or 2) + 0.5))
    local offset = tonumber(cfg.focusOffset) or 0
    for i = 1, #keys do
        local key = keys[i]
        local edge = frame.MSUFGFFocusEdges[key]
        if not edge then
            edge = frame:CreateTexture(nil, "OVERLAY", nil, 6)
            frame.MSUFGFFocusEdges[key] = edge
        end
        LayoutTargetEdge(frame, edge, key, size + offset)
        edge:SetColorTexture(cfg.focusR or 0.5, cfg.focusG or 0.5, cfg.focusB or 1, 1)
        SetShown(edge, true)
    end
end

local function UpdateHealthFade(frame, cfg)
    if not frame.hpBar then return end
    local alpha = min(max(tonumber(cfg.hpBarAlpha) or 1, 0), 1)
    if cfg.healthFadeEnabled == true and frame.unit then
        local pct
        if UnitHealthPercent then
            local raw = UnitHealthPercent(frame.unit)
            pct = tonumber(raw)
        end
        if pct == nil and UnitHealth and UnitHealthMax then
            local hp, maxHP = UnitHealth(frame.unit), UnitHealthMax(frame.unit)
            hp, maxHP = tonumber(hp), tonumber(maxHP)
            if hp and maxHP and maxHP > 0 then
                pct = (hp / maxHP) * 100
            end
        end
        if pct and pct >= (cfg.healthFadeThreshold or 95) then
            alpha = alpha * (cfg.healthFadeAlpha or 0.45)
        end
    end
    alpha = alpha * (tonumber(frame._msufGFRangeHealthAlpha) or 1)
    frame.hpBar:SetAlpha(alpha)
    frame._msufGFVisualHealthAlpha = alpha
    local textAlpha = cfg.hpTextIgnoreAlpha == false and alpha or 1
    if frame.hpText then frame.hpText:SetAlpha(textAlpha) end
    if frame.hpTextLeft then frame.hpTextLeft:SetAlpha(textAlpha) end
    if frame.hpTextCenter then frame.hpTextCenter:SetAlpha(textAlpha) end
    if frame.hpTextRight then frame.hpTextRight:SetAlpha(textAlpha) end
    local alphaCfg = frame.MSUFSpec and frame.MSUFSpec.alpha
    if not (alphaCfg and alphaCfg.active == true and alphaCfg.layered == true) then
        local bgAlpha = min(max(tonumber(cfg.hpBgAlpha) or 1, 0), 1) * (tonumber(frame._msufGFRangeHealthAlpha) or 1)
        if frame.bg then frame.bg:SetAlpha(bgAlpha) end
        if frame.hpBarBG and frame.hpBarBG ~= frame.bg then frame.hpBarBG:SetAlpha(bgAlpha) end
    end
end

local function UpdateStripe(frame, cfg, snapshot)
    local tex = EnsureTexture(frame, "MSUFGFDebuffStripe", "OVERLAY")
    if not (cfg.debuffStripeEnabled == true and snapshot and snapshot.anyDebuff) then
        SetShown(tex, false)
        return
    end
    tex:ClearAllPoints()
    if cfg.debuffStripeEdge == "TOP" then
        tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    else
        tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    end
    tex:SetHeight(cfg.debuffStripeHeight or 3)
    tex:SetColorTexture(cfg.debuffStripeColorR or 0.8, cfg.debuffStripeColorG or 0.2, cfg.debuffStripeColorB or 0.2, cfg.debuffStripeAlpha or 0.6)
    SetShown(tex, true)
end

local function DebuffLaneState(frame)
    local lane = frame and frame.Auras and frame.Auras.Debuffs or frame and frame.Debuffs
    if not lane then
        return nil
    end
    local anyDebuff = (tonumber(lane.visibleButtons) or 0) > 0
    local byMe = false
    local active, all = lane.active, lane.all
    if type(active) == "table" and type(all) == "table" then
        for auraInstanceID in next, active do
            anyDebuff = true
            local data = all[auraInstanceID]
            if data and data.isPlayerAura == true then
                byMe = true
            end
        end
    end
    return {
        anyDebuff = anyDebuff,
        dispellable = lane._msufBorderAuraState == "dispel",
        anyDispelType = lane._msufBorderAuraState == "dispel",
        byMe = byMe,
    }
end

local function FallbackAuraSnapshot(frame, event, updateInfo)
    if event == "UNIT_AURA" and AuraCache.UpdateSnapshot then
        return AuraCache.UpdateSnapshot(frame, updateInfo)
    end
    if event == "MSUF_GF_VISUALS_APPLY" and AuraCache.GetSnapshot then
        return AuraCache.GetSnapshot(frame)
    end
    return frame and frame._msufGFAuraSnapshot or nil
end

local function AuraSnapshot(frame, event, updateInfo)
    return DebuffLaneState(frame) or FallbackAuraSnapshot(frame, event, updateInfo)
end

local function SpecNeedsAuraSnapshot(spec)
    local cfg = spec and spec.group
    if not cfg then return false end
    if cfg.dispelOverlayEnabled == true or cfg.debuffStripeEnabled == true then
        return true
    end
    local border = spec and spec.border
    return border and border.dispel == true
end

local function NeedsAuraSnapshot(frame, cfg)
    return SpecNeedsAuraSnapshot(frame and frame.MSUFSpec)
end

local function DispelOverlayActive(cfg, snapshot)
    if not snapshot then return false end
    local trigger = cfg.dispelOverlayTrigger or "BORDER"
    if trigger == "ANY_DEBUFF" then
        return snapshot.anyDebuff == true
    elseif trigger == "DISPEL_TYPE" then
        return snapshot.anyDispelType == true or snapshot.dispellable == true
    elseif trigger == "BY_ME" then
        return snapshot.byMe == true
    end
    return snapshot.dispellable == true
end

local function OverlayTarget(frame, cfg)
    if cfg.dispelOverlayOnHealth ~= false and frame.hpBar then
        if frame.hpBar.GetStatusBarTexture then
            local tex = frame.hpBar:GetStatusBarTexture()
            if tex then return tex end
        end
        return frame.hpBar
    end
    return frame
end

local function LayoutOverlayStyle(tex, frame, cfg)
    local target = OverlayTarget(frame, cfg)
    local style = cfg.dispelOverlayStyle or "FULL"
    local h = frame.GetHeight and frame:GetHeight() or 16
    local thickness = max(2, floor((tonumber(h) or 16) * 0.18 + 0.5))
    tex:ClearAllPoints()
    if style == "TOP" then
        tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        tex:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        tex:SetHeight(thickness)
    elseif style == "BOTTOM" then
        tex:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        tex:SetHeight(thickness)
    elseif style == "LEFT" then
        tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        tex:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        tex:SetWidth(thickness)
    elseif style == "RIGHT" then
        tex:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        tex:SetWidth(thickness)
    else
        tex:SetAllPoints(target)
    end
end

local function UpdateDispelOverlay(frame, cfg, snapshot)
    local tex = EnsureTexture(frame, "MSUFGFDispelOverlay", "OVERLAY")
    if not (cfg.dispelOverlayEnabled == true and DispelOverlayActive(cfg, snapshot)) then
        SetShown(tex, false)
        return
    end
    LayoutOverlayStyle(tex, frame, cfg)
    tex:SetColorTexture(0.25, 0.75, 1, cfg.dispelOverlayAlpha or 0.35)
    SetShown(tex, true)
end

local GroupVisuals = {}

function GroupVisuals.IsEnabled(frame, spec)
    return spec and spec.scope == "group" and spec.group ~= nil
end

function GroupVisuals.GetEvents(frame, spec)
    local cfg = spec and spec.group
    if not cfg then return EMPTY_EVENTS end
    local health = cfg.healthFadeEnabled == true
    local aura = SpecNeedsAuraSnapshot(spec) == true
    if health and aura then return VISUAL_HEALTH_AURA_EVENTS end
    if health then return VISUAL_HEALTH_EVENTS end
    if aura then return VISUAL_AURA_EVENTS end
    return EMPTY_EVENTS
end

function GroupVisuals.GetUnitlessEvents(frame, spec)
    local cfg = spec and spec.group
    if not cfg then return EMPTY_EVENTS end
    local target = cfg.targetIndicator == true
    local focus = cfg.focusIndicator == true
    if target and focus then return VISUAL_TARGET_FOCUS_EVENTS end
    if target then return VISUAL_TARGET_EVENT end
    if focus then return VISUAL_FOCUS_EVENT end
    return EMPTY_EVENTS
end

local function UpdateVisuals(frame, event, updateInfo)
    local cfg = GroupSpec(frame)
    if not cfg then return end
    local spec = frame.MSUFSpec
    local needsSnapshot = NeedsAuraSnapshot(frame, cfg)
    local snapshot = needsSnapshot and AuraSnapshot(frame, event, updateInfo) or nil
    local border = spec and spec.border
    local borderAuraEnabled = border and border.dispel == true
    frame._msufGFBorderAuraStateKnown = true
    frame._msufGFBorderAuraEnabled = borderAuraEnabled and true or false
    frame._msufGFBorderAuraState = borderAuraEnabled and snapshot and snapshot.dispellable and "dispel" or nil
    local debuffs = frame.Auras and frame.Auras.Debuffs
    if debuffs then
        debuffs._msufBorderAuraStateKnown = true
        debuffs._msufBorderAuraEnabled = borderAuraEnabled and true or false
        debuffs._msufBorderAuraState = frame._msufGFBorderAuraState
    end

    UpdateTarget(frame, cfg)
    UpdateFocus(frame, cfg)
    UpdateHealthFade(frame, cfg)
    UpdateStripe(frame, cfg, snapshot)
    UpdateDispelOverlay(frame, cfg, snapshot)

    -- Borders reads frame._msufGFBorderAuraState set above. The core dispatcher
    -- already runs Borders.Update AFTER GroupVisuals for aura/threat events
    -- (kind 5, 6), so explicitly poking Borders there would fire it twice.
    -- We only need the explicit refresh on Apply/non-dispatched flows where
    -- Borders.Apply ran first (via elementOrder) and saw stale state.
    if event == "MSUF_GF_VISUALS_APPLY" or event == "MSUF_GF_RANGE_ALPHA" then
        local borders = UF.elements and UF.elements.Borders
        if borders and borders.Update then
            borders.Update(frame, "MSUF_GF_VISUALS", frame.unit)
        end
    end
end

function GroupVisuals.Apply(frame) UpdateVisuals(frame, "MSUF_GF_VISUALS_APPLY") end
function GroupVisuals.Update(frame, event, unit, updateInfo) UpdateVisuals(frame, event, updateInfo) end

UF.RegisterElement("GroupVisuals", GroupVisuals)
