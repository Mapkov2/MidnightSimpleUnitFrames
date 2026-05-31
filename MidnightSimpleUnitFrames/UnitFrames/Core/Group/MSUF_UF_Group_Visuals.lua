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
local DispelState = UF and UF.DispelState or {}
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitHealthPercent = UnitHealthPercent
local UnitIsUnit = UnitIsUnit
local tonumber = tonumber
local max = math.max
local floor = math.floor
local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end
local IsNil = Secrets.IsNil or function(value) return value == nil end

local EMPTY_EVENTS = {}
local MEDIA_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\"
local DISPEL_OVERLAY_TEXTURES = {
    TOP = MEDIA_ROOT .. "MSUF_Grad_V.tga",
    BOTTOM = MEDIA_ROOT .. "MSUF_Grad_V_Rev.tga",
    LEFT = MEDIA_ROOT .. "MSUF_Grad_H.tga",
    RIGHT = MEDIA_ROOT .. "MSUF_Grad_H_Rev.tga",
}
local VISUAL_HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local VISUAL_AURA_EVENTS = { "UNIT_AURA" }
local VISUAL_HEALTH_AURA_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA" }
local VISUAL_TARGET_EVENT = { "PLAYER_TARGET_CHANGED" }
local VISUAL_FOCUS_EVENT = { "PLAYER_FOCUS_CHANGED" }
local VISUAL_TARGET_FOCUS_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED" }
local VISUAL_DISPEL_EVENTS = {
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "SPELLS_CHANGED",
}
local VISUAL_TARGET_DISPEL_EVENTS = {
    "PLAYER_TARGET_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "SPELLS_CHANGED",
}
local VISUAL_FOCUS_DISPEL_EVENTS = {
    "PLAYER_FOCUS_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "SPELLS_CHANGED",
}
local VISUAL_TARGET_FOCUS_DISPEL_EVENTS = {
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "SPELLS_CHANGED",
}
local EDGE_KEYS = { "top", "bottom", "left", "right" }

local function IsDispelCapabilityEvent(event)
    return event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "SPELLS_CHANGED"
end

local function AuraBackendEnabled()
    local a3 = MSUF and (MSUF.MSUF_Auras3 or _G.MSUF_Auras3)
    return a3 and type(a3.BackendEnabled) == "function" and a3.BackendEnabled() == true
end

local function EnsureTexture(frame, key, layer)
    local tex = frame[key]
    if not tex then
        tex = frame:CreateTexture(nil, layer or "OVERLAY")
        frame[key] = tex
    end
    return tex
end

local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then
        value = fallback or 1
    end
    if value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

local function SetAlphaCached(region, alpha, key)
    if not (region and region.SetAlpha) then return end
    alpha = Clamp01(alpha, 1)
    key = key or "_msufGFVisualAlpha"
    if region[key] ~= alpha then
        region:SetAlpha(alpha)
        region[key] = alpha
    end
end

local function SetHeightCached(region, height, key)
    if not (region and region.SetHeight) then return end
    height = tonumber(height) or 0
    key = key or "_msufGFVisualHeight"
    if region[key] ~= height then
        region:SetHeight(height)
        region[key] = height
    end
end

local function SetWidthCached(region, width, key)
    if not (region and region.SetWidth) then return end
    width = tonumber(width) or 0
    key = key or "_msufGFVisualWidth"
    if region[key] ~= width then
        region:SetWidth(width)
        region[key] = width
    end
end

local function SetTextureCached(tex, texture)
    if not (tex and tex.SetTexture) then return end
    if tex._msufGFVisualTextureKind ~= "texture" or tex._msufGFVisualTexture ~= texture then
        tex:SetTexture(texture)
        tex._msufGFVisualTextureKind = "texture"
        tex._msufGFVisualTexture = texture
        tex._msufGFVisualColorR = nil
        tex._msufGFVisualColorG = nil
        tex._msufGFVisualColorB = nil
        tex._msufGFVisualColorA = nil
    end
end

local function SetVertexColorCached(tex, r, g, b, a)
    if not (tex and tex.SetVertexColor) then return end
    r, g, b, a = r or 1, g or 1, b or 1, a or 1
    if tex._msufGFVisualVertexR ~= r or tex._msufGFVisualVertexG ~= g
        or tex._msufGFVisualVertexB ~= b or tex._msufGFVisualVertexA ~= a then
        tex:SetVertexColor(r, g, b, a)
        tex._msufGFVisualVertexR = r
        tex._msufGFVisualVertexG = g
        tex._msufGFVisualVertexB = b
        tex._msufGFVisualVertexA = a
    end
end

local function SetColorTextureCached(tex, r, g, b, a)
    if not (tex and tex.SetColorTexture) then return end
    r, g, b, a = r or 1, g or 1, b or 1, a or 1
    if tex._msufGFVisualTextureKind ~= "color" or tex._msufGFVisualColorR ~= r
        or tex._msufGFVisualColorG ~= g or tex._msufGFVisualColorB ~= b
        or tex._msufGFVisualColorA ~= a then
        tex:SetColorTexture(r, g, b, a)
        tex._msufGFVisualTextureKind = "color"
        tex._msufGFVisualTexture = nil
        tex._msufGFVisualVertexR = nil
        tex._msufGFVisualVertexG = nil
        tex._msufGFVisualVertexB = nil
        tex._msufGFVisualVertexA = nil
        tex._msufGFVisualColorR = r
        tex._msufGFVisualColorG = g
        tex._msufGFVisualColorB = b
        tex._msufGFVisualColorA = a
    end
end

local function LayoutTargetEdge(parent, edge, key, size)
    if edge._msufGFEdgeLayoutParent == parent
        and edge._msufGFEdgeLayoutKey == key
        and edge._msufGFEdgeLayoutSize == size then
        return
    end
    edge:ClearAllPoints()
    if key == "top" then
        edge:SetPoint("TOPLEFT", parent, "TOPLEFT", -size, size)
        edge:SetPoint("TOPRIGHT", parent, "TOPRIGHT", size, size)
        SetHeightCached(edge, size, "_msufGFEdgeHeight")
    elseif key == "bottom" then
        edge:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -size, -size)
        edge:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", size, -size)
        SetHeightCached(edge, size, "_msufGFEdgeHeight")
    elseif key == "left" then
        edge:SetPoint("TOPLEFT", parent, "TOPLEFT", -size, size)
        edge:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -size, -size)
        SetWidthCached(edge, size, "_msufGFEdgeWidth")
    else
        edge:SetPoint("TOPRIGHT", parent, "TOPRIGHT", size, size)
        edge:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", size, -size)
        SetWidthCached(edge, size, "_msufGFEdgeWidth")
    end
    edge._msufGFEdgeLayoutParent = parent
    edge._msufGFEdgeLayoutKey = key
    edge._msufGFEdgeLayoutSize = size
end

local function HideEdges(edges)
    if not edges then return end
    for i = 1, #EDGE_KEYS do
        SetShown(edges[EDGE_KEYS[i]], false)
    end
end

local function UpdateTarget(frame, cfg)
    local show = false
    if cfg.targetIndicator == true and UnitIsUnit and frame.unit then
        local same = UnitIsUnit(frame.unit, "target")
        show = same == true or same == 1
    end
    if not show then
        HideEdges(frame.MSUFGFTargetEdges)
        return
    end
    frame.MSUFGFTargetEdges = frame.MSUFGFTargetEdges or {}
    for i = 1, #EDGE_KEYS do
        local key = EDGE_KEYS[i]
        local edge = frame.MSUFGFTargetEdges[key]
        if not edge then
            edge = frame:CreateTexture(nil, "OVERLAY", nil, 7)
            frame.MSUFGFTargetEdges[key] = edge
        end
        LayoutTargetEdge(frame, edge, key, 2)
        SetColorTextureCached(edge, cfg.targetR or 1, cfg.targetG or 1, cfg.targetB or 1, 1)
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
        HideEdges(frame.MSUFGFFocusEdges)
        return
    end
    frame.MSUFGFFocusEdges = frame.MSUFGFFocusEdges or {}
    local size = max(1, floor((tonumber(cfg.focusSize) or 2) + 0.5))
    local offset = tonumber(cfg.focusOffset) or 0
    for i = 1, #EDGE_KEYS do
        local key = EDGE_KEYS[i]
        local edge = frame.MSUFGFFocusEdges[key]
        if not edge then
            edge = frame:CreateTexture(nil, "OVERLAY", nil, 6)
            frame.MSUFGFFocusEdges[key] = edge
        end
        LayoutTargetEdge(frame, edge, key, size + offset)
        SetColorTextureCached(edge, cfg.focusR or 0.5, cfg.focusG or 0.5, cfg.focusB or 1, 1)
        SetShown(edge, true)
    end
end

local function PercentFromValues(hp, maxHP)
    if IsNil(hp) or IsNil(maxHP) or IsSecret(hp) or IsSecret(maxHP) then
        return nil
    end
    hp, maxHP = tonumber(hp), tonumber(maxHP)
    if hp and maxHP and maxHP > 0 then
        return (hp / maxHP) * 100
    end
    return nil
end

local function UpdateHealthFade(frame, cfg, seedHP, seedMaxHP)
    if not frame.hpBar then return end
    local alpha = Clamp01(cfg.hpBarAlpha, 1)
    if cfg.healthFadeEnabled == true and frame.unit then
        local pct = PercentFromValues(seedHP, seedMaxHP)
        if pct == nil and UnitHealthPercent then
            local raw = UnitHealthPercent(frame.unit)
            if not IsSecret(raw) then
                pct = tonumber(raw)
            end
        end
        if pct == nil and IsNil(seedHP) and IsNil(seedMaxHP) and UnitHealth and UnitHealthMax then
            local hp, maxHP = UnitHealth(frame.unit), UnitHealthMax(frame.unit)
            pct = PercentFromValues(hp, maxHP)
        end
        if pct and pct >= (cfg.healthFadeThreshold or 95) then
            alpha = alpha * (cfg.healthFadeAlpha or 0.45)
        end
    end
    alpha = alpha * (tonumber(frame._msufGFRangeHealthAlpha) or 1)
    SetAlphaCached(frame.hpBar, alpha, "_msufGFVisualHealthAlpha")
    frame._msufGFVisualHealthAlpha = alpha
    local textAlpha = cfg.hpTextIgnoreAlpha == false and alpha or 1
    SetAlphaCached(frame.hpText, textAlpha, "_msufGFVisualTextAlpha")
    SetAlphaCached(frame.hpTextLeft, textAlpha, "_msufGFVisualTextAlpha")
    SetAlphaCached(frame.hpTextCenter, textAlpha, "_msufGFVisualTextAlpha")
    SetAlphaCached(frame.hpTextRight, textAlpha, "_msufGFVisualTextAlpha")
    local alphaCfg = frame.MSUFSpec and frame.MSUFSpec.alpha
    if not (alphaCfg and alphaCfg.active == true and alphaCfg.layered == true) then
        local bgAlpha = Clamp01(cfg.hpBgAlpha, 1) * (tonumber(frame._msufGFRangeHealthAlpha) or 1)
        SetAlphaCached(frame.bg, bgAlpha, "_msufGFVisualBgAlpha")
        if frame.hpBarBG and frame.hpBarBG ~= frame.bg then
            SetAlphaCached(frame.hpBarBG, bgAlpha, "_msufGFVisualBgAlpha")
        end
    end
end

local function UpdateStripe(frame, cfg, snapshot)
    if cfg.debuffStripeEnabled ~= true then
        SetShown(frame.MSUFGFDebuffStripe, false)
        return
    end
    local tex = EnsureTexture(frame, "MSUFGFDebuffStripe", "OVERLAY")
    if not (snapshot and snapshot.anyDebuff) then
        SetShown(tex, false)
        return
    end
    local edge = cfg.debuffStripeEdge == "TOP" and "TOP" or "BOTTOM"
    if tex._msufGFStripeEdge ~= edge then
        tex:ClearAllPoints()
        if edge == "TOP" then
            tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        else
            tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
        tex._msufGFStripeEdge = edge
    end
    SetHeightCached(tex, cfg.debuffStripeHeight or 3, "_msufGFStripeHeight")
    SetColorTextureCached(tex, cfg.debuffStripeColorR or 0.8, cfg.debuffStripeColorG or 0.2, cfg.debuffStripeColorB or 0.2, cfg.debuffStripeAlpha or 0.6)
    SetShown(tex, true)
end

local function SpecNeedsAuraSnapshot(spec)
    if not AuraBackendEnabled() then return false end
    local cfg = spec and spec.group
    if not cfg then return false end
    if cfg.dispelOverlayEnabled == true or cfg.debuffStripeEnabled == true then
        return true
    end
    local border = spec and spec.border
    return border and border.dispel == true
end

local function TriggerNeedsCapability(trigger)
    trigger = DispelState.NormalizeOverlayTrigger and DispelState.NormalizeOverlayTrigger(trigger) or trigger
    return trigger == "BY_ME" or trigger == "BORDER"
end

local function SpecNeedsDispelCapability(spec)
    if not AuraBackendEnabled() then return false end
    local cfg = spec and spec.group
    local border = spec and spec.border
    if border and border.dispel == true and TriggerNeedsCapability(border.dispelTrigger or "BY_ME") then
        return true
    end
    if cfg and cfg.dispelOverlayEnabled == true then
        local trigger = cfg.dispelOverlayTrigger or "BORDER"
        if trigger == "BORDER" then
            if not border or border.dispel ~= true then return true end
            return TriggerNeedsCapability(border.dispelTrigger or "BY_ME")
        end
        return TriggerNeedsCapability(trigger)
    end
    return false
end

local function SpecNeedsGroupVisuals(spec)
    local cfg = spec and spec.group
    if not cfg then return false end
    return cfg.healthFadeEnabled == true
        or cfg.targetIndicator == true
        or cfg.focusIndicator == true
        or SpecNeedsAuraSnapshot(spec) == true
        or SpecNeedsDispelCapability(spec) == true
end

local function CompileRuntimeFlags(frame, spec)
    if not frame then return end
    local cfg = spec and spec.group
    frame._msufGFVisualHealthFade = cfg and cfg.healthFadeEnabled == true or nil
    frame._msufGFVisualAuraSnapshot = SpecNeedsAuraSnapshot(spec) == true or nil
    frame._msufGFVisualTarget = cfg and cfg.targetIndicator == true or nil
    frame._msufGFVisualFocus = cfg and cfg.focusIndicator == true or nil
end

local function NeedsAuraSnapshot(frame)
    return frame and frame._msufGFVisualAuraSnapshot == true
end

local function TriggerNeeds(trigger, needs)
    trigger = DispelState.NormalizeOverlayTrigger and DispelState.NormalizeOverlayTrigger(trigger) or trigger
    if trigger == "ANY_DEBUFF" then
        needs.anyDebuff = true
    elseif trigger == "DISPEL_TYPE" then
        needs.anyDispelType = true
    elseif trigger == "PLAYER_CAST" then
        needs.playerCast = true
    else
        needs.dispellable = true
    end
end

local function AuraSnapshot(frame, cfg, spec)
    if not (DispelState and DispelState.Update) then return nil end
    local border = spec and spec.border
    local needs = frame._msufGFDispelNeeds
    if not needs then
        needs = {}
        frame._msufGFDispelNeeds = needs
    end
    needs.anyDebuff = cfg and cfg.debuffStripeEnabled == true
    needs.anyDispelType = false
    needs.dispellable = false
    needs.playerCast = false
    if border and border.dispel == true then
        TriggerNeeds(border.dispelTrigger or "BY_ME", needs)
    end
    if cfg and cfg.dispelOverlayEnabled == true then
        local trigger = cfg.dispelOverlayTrigger or "BORDER"
        if trigger == "BORDER" and border and border.dispel == true then
            TriggerNeeds(border.dispelTrigger or "BY_ME", needs)
        else
            TriggerNeeds(trigger, needs)
        end
    end

    local options = frame._msufGFDispelOptions
    if not options then
        options = {}
        frame._msufGFDispelOptions = options
    end
    options.needAnyDebuff = needs.anyDebuff
    options.needAnyDispelType = needs.anyDispelType
    options.needDispellable = needs.dispellable
    options.needPlayerCast = needs.playerCast
    local snapshot = DispelState.Update(frame, options)
    if not snapshot then return nil end

    local borderTrigger = border and border.dispelTrigger or "BY_ME"
    snapshot.borderTrigger = borderTrigger
    snapshot.borderActive = border and border.dispel == true
        and DispelState.ActiveForTrigger(snapshot, borderTrigger, false) == true
    if snapshot.borderActive then
        snapshot.borderAuraInstanceID = DispelState.AuraIDForTrigger(snapshot, borderTrigger)
        snapshot.borderR, snapshot.borderG, snapshot.borderB, snapshot.borderA =
            DispelState.ColorForTrigger(snapshot, borderTrigger, spec and spec.dispel, 1)
    end

    local overlayTrigger = cfg and cfg.dispelOverlayTrigger or "BORDER"
    snapshot.overlayTrigger = overlayTrigger
    local overlayActiveTrigger = overlayTrigger == "BORDER" and not (border and border.dispel == true) and "BY_ME" or overlayTrigger
    snapshot.overlayActive = cfg and cfg.dispelOverlayEnabled == true
        and DispelState.ActiveForTrigger(snapshot, overlayActiveTrigger, snapshot.borderActive) == true
    if snapshot.overlayActive then
        local colorTrigger = overlayTrigger == "BORDER" and border and border.dispel == true and borderTrigger or overlayActiveTrigger
        snapshot.overlayAuraInstanceID = DispelState.AuraIDForTrigger(snapshot, colorTrigger)
        snapshot.overlayR, snapshot.overlayG, snapshot.overlayB, snapshot.overlayA =
            DispelState.ColorForTrigger(snapshot, colorTrigger, spec and spec.dispel, cfg.dispelOverlayAlpha or 0.35)
    end
    return snapshot
end

local function HideDispelOverlays(frame, except)
    local tex = frame and frame.MSUFGFDispelOverlay
    if tex and tex ~= except then SetShown(tex, false) end
    tex = frame and frame.MSUFGFDispelOverlayFrame
    if tex and tex ~= except then SetShown(tex, false) end
    tex = frame and frame.MSUFGFDispelOverlayHealth
    if tex and tex ~= except then SetShown(tex, false) end
end

local function EnsureDispelOverlayLayer(frame)
    local layer = frame.MSUFGFDispelOverlayLayer
    if not layer then
        layer = CreateFrame("Frame", nil, frame)
        layer:SetAllPoints(frame)
        layer:EnableMouse(false)
        frame.MSUFGFDispelOverlayLayer = layer
    end
    if layer.SetFrameLevel and frame.GetFrameLevel then
        local level = (frame:GetFrameLevel() or 1) + 35
        if layer._msufDispelOverlayLevel ~= level then
            layer:SetFrameLevel(level)
            layer._msufDispelOverlayLevel = level
        end
    end
    return layer
end

local function DispelOverlayParent(frame, cfg)
    if cfg and cfg.dispelOverlayOnHealth ~= false and frame.hpBar and frame.hpBar.CreateTexture then
        return frame.hpBar, "MSUFGFDispelOverlayHealth"
    end
    return EnsureDispelOverlayLayer(frame), "MSUFGFDispelOverlayFrame"
end

local function EnsureDispelOverlay(frame, cfg)
    local parent, key = DispelOverlayParent(frame, cfg)
    local tex = frame[key]
    if not tex then
        tex = parent:CreateTexture(nil, "OVERLAY")
        if tex.SetDrawLayer then
            tex:SetDrawLayer("OVERLAY", 7)
        end
        tex:SetColorTexture(0.25, 0.75, 1, 0.35)
        tex:SetBlendMode("BLEND")
        tex:Hide()
        frame[key] = tex
    end
    frame.MSUFGFDispelOverlay = tex
    HideDispelOverlays(frame, tex)
    return tex
end

local function OverlayTarget(frame, cfg)
    if cfg.dispelOverlayOnHealth ~= false and frame.hpBar then
        return frame.hpBar
    end
    return frame
end

local function LayoutOverlayStyle(tex, frame, cfg)
    local target = OverlayTarget(frame, cfg)
    local style = cfg.dispelOverlayStyle or "FULL"
    local h = frame.GetHeight and frame:GetHeight() or 16
    local thickness = max(2, floor((tonumber(h) or 16) * 0.18 + 0.5))
    if tex._msufGFOverlayTarget == target
        and tex._msufGFOverlayStyle == style
        and tex._msufGFOverlayThickness == thickness then
        return
    end
    tex:ClearAllPoints()
    if style == "TOP" then
        tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        tex:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        SetHeightCached(tex, thickness, "_msufGFOverlayHeight")
    elseif style == "BOTTOM" then
        tex:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        SetHeightCached(tex, thickness, "_msufGFOverlayHeight")
    elseif style == "LEFT" then
        tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        tex:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        SetWidthCached(tex, thickness, "_msufGFOverlayWidth")
    elseif style == "RIGHT" then
        tex:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        SetWidthCached(tex, thickness, "_msufGFOverlayWidth")
    else
        tex:SetAllPoints(target)
    end
    tex._msufGFOverlayTarget = target
    tex._msufGFOverlayStyle = style
    tex._msufGFOverlayThickness = thickness
end

local function OverlayAlpha(alpha, cfg, spec)
    alpha = tonumber(alpha) or tonumber(cfg and cfg.dispelOverlayAlpha) or 0.35
    if cfg and cfg.dispelOverlayOnHealth ~= false
        and (cfg.dispelOverlayStyle or "FULL") == "FULL"
        and spec and spec.health and spec.health.mode == "dark"
        and alpha > 0.18 then
        return 0.18
    end
    return alpha
end

local function PaintOverlay(tex, style, r, g, b, a)
    local texture = DISPEL_OVERLAY_TEXTURES[style or "FULL"]
    if texture then
        SetTextureCached(tex, texture)
        SetVertexColorCached(tex, r, g, b, a)
    else
        SetColorTextureCached(tex, r, g, b, a)
    end
end

local function UpdateDispelOverlay(frame, cfg, snapshot, spec)
    if not (cfg.dispelOverlayEnabled == true and snapshot and snapshot.overlayActive == true) then
        HideDispelOverlays(frame)
        return
    end
    local tex = EnsureDispelOverlay(frame, cfg)
    LayoutOverlayStyle(tex, frame, cfg)
    PaintOverlay(tex, cfg.dispelOverlayStyle,
        snapshot.overlayR or 0.25,
        snapshot.overlayG or 0.75,
        snapshot.overlayB or 1,
        OverlayAlpha(snapshot.overlayA, cfg, spec))
    SetShown(tex, true)
end

local GroupVisuals = {}

function GroupVisuals.IsEnabled(frame, spec)
    return spec and spec.scope == "group" and SpecNeedsGroupVisuals(spec) == true
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
    local capability = SpecNeedsDispelCapability(spec) == true
    local target = cfg.targetIndicator == true
    local focus = cfg.focusIndicator == true
    if capability and target and focus then return VISUAL_TARGET_FOCUS_DISPEL_EVENTS end
    if capability and target then return VISUAL_TARGET_DISPEL_EVENTS end
    if capability and focus then return VISUAL_FOCUS_DISPEL_EVENTS end
    if capability then return VISUAL_DISPEL_EVENTS end
    if target and focus then return VISUAL_TARGET_FOCUS_EVENTS end
    if target then return VISUAL_TARGET_EVENT end
    if focus then return VISUAL_FOCUS_EVENT end
    return EMPTY_EVENTS
end

local function SetBorderAuraState(frame, borderAuraEnabled, snapshot)
    if not frame then return end
    frame._msufGFBorderAuraStateKnown = true
    frame._msufGFBorderAuraEnabled = borderAuraEnabled and true or false
    frame._msufGFBorderAuraState = borderAuraEnabled and snapshot and snapshot.borderActive and "dispel" or nil
    frame._msufGFBorderAuraColorR = snapshot and snapshot.borderR or nil
    frame._msufGFBorderAuraColorG = snapshot and snapshot.borderG or nil
    frame._msufGFBorderAuraColorB = snapshot and snapshot.borderB or nil
    frame._msufGFBorderAuraColorA = snapshot and snapshot.borderA or nil
    local debuffs = frame.Auras and frame.Auras.Debuffs
    if debuffs then
        debuffs._msufBorderAuraStateKnown = true
        debuffs._msufBorderAuraEnabled = borderAuraEnabled and true or false
        debuffs._msufBorderAuraState = frame._msufGFBorderAuraState
        debuffs._msufBorderAuraColorR = frame._msufGFBorderAuraColorR
        debuffs._msufBorderAuraColorG = frame._msufGFBorderAuraColorG
        debuffs._msufBorderAuraColorB = frame._msufGFBorderAuraColorB
        debuffs._msufBorderAuraColorA = frame._msufGFBorderAuraColorA
    end
end

local function UpdateBordersFromVisualState(frame)
    local active = frame and frame._msufActiveElements
    local borders = active and active.Borders == true and UF.elements and UF.elements.Borders
    if borders and borders.Update then
        borders.Update(frame, "MSUF_GF_VISUALS", frame.unit)
    end
end

local function UpdateAuraLanes(frame, cfg, spec, updateBorders)
    local snapshot = NeedsAuraSnapshot(frame) and AuraSnapshot(frame, cfg, spec) or nil
    local border = spec and spec.border
    SetBorderAuraState(frame, border and border.dispel == true, snapshot)
    UpdateStripe(frame, cfg, snapshot)
    UpdateDispelOverlay(frame, cfg, snapshot, spec)
    if updateBorders then
        UpdateBordersFromVisualState(frame)
    end
end

local function UpdateVisuals(frame, event, updateInfo, seedMaxHP)
    local spec = frame.MSUFSpec
    local cfg = spec and spec.group
    if not cfg then return end

    if event == "PLAYER_TARGET_CHANGED" then
        if frame._msufGFVisualTarget == true then
            UpdateTarget(frame, cfg)
        end
        return
    elseif event == "PLAYER_FOCUS_CHANGED" then
        if frame._msufGFVisualFocus == true then
            UpdateFocus(frame, cfg)
        end
        return
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if frame._msufGFVisualHealthFade == true then
            UpdateHealthFade(frame, cfg, updateInfo, seedMaxHP)
        end
        return
    elseif event == "MSUF_GF_RANGE_ALPHA" then
        UpdateHealthFade(frame, cfg)
        UpdateBordersFromVisualState(frame)
        return
    elseif event == "UNIT_AURA" or IsDispelCapabilityEvent(event) then
        if frame._msufGFVisualAuraSnapshot == true then
            UpdateAuraLanes(frame, cfg, spec, true)
        end
        return
    end

    UpdateTarget(frame, cfg)
    UpdateFocus(frame, cfg)
    UpdateHealthFade(frame, cfg)
    UpdateAuraLanes(frame, cfg, spec, false)

    -- Borders no longer owns UNIT_AURA. GroupVisuals computes the shared
    -- snapshot once, then pokes the border from here so aura + border never
    -- perform separate scans for the same frame/event.
    if event == "MSUF_GF_VISUALS_APPLY" then
        UpdateBordersFromVisualState(frame)
    end
end

local function ClearBorderAuraState(frame)
    if not frame then return end
    frame._msufGFBorderAuraStateKnown = true
    frame._msufGFBorderAuraEnabled = false
    frame._msufGFBorderAuraState = nil
    frame._msufGFBorderAuraColorR = nil
    frame._msufGFBorderAuraColorG = nil
    frame._msufGFBorderAuraColorB = nil
    frame._msufGFBorderAuraColorA = nil
    local debuffs = frame.Auras and frame.Auras.Debuffs
    if debuffs then
        debuffs._msufBorderAuraStateKnown = true
        debuffs._msufBorderAuraEnabled = false
        debuffs._msufBorderAuraState = nil
        debuffs._msufBorderAuraColorR = nil
        debuffs._msufBorderAuraColorG = nil
        debuffs._msufBorderAuraColorB = nil
        debuffs._msufBorderAuraColorA = nil
    end
end

function GroupVisuals.Apply(frame)
    CompileRuntimeFlags(frame, frame and frame.MSUFSpec)
    UpdateVisuals(frame, "MSUF_GF_VISUALS_APPLY")
end
function GroupVisuals.Update(frame, event, unit, updateInfo, seedMaxHP) UpdateVisuals(frame, event, updateInfo, seedMaxHP) end

function GroupVisuals.Disable(frame)
    if not frame then return end
    frame._msufGFVisualHealthFade = nil
    frame._msufGFVisualAuraSnapshot = nil
    frame._msufGFVisualTarget = nil
    frame._msufGFVisualFocus = nil
    HideEdges(frame.MSUFGFTargetEdges)
    HideEdges(frame.MSUFGFFocusEdges)
    SetShown(frame.MSUFGFDebuffStripe, false)
    HideDispelOverlays(frame)
    ClearBorderAuraState(frame)
end

UF.RegisterElement("GroupVisuals", GroupVisuals)
