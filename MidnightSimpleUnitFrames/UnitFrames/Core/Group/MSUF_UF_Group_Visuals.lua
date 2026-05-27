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
local min = math.min
local max = math.max
local floor = math.floor

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

local function IsDispelCapabilityEvent(event)
    return event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "SPELLS_CHANGED"
end

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

local function SpecNeedsAuraSnapshot(spec)
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

local function NeedsAuraSnapshot(frame)
    return SpecNeedsAuraSnapshot(frame and frame.MSUFSpec)
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
        tex:SetTexture(texture)
        tex:SetVertexColor(r, g, b, a)
    else
        tex:SetColorTexture(r, g, b, a)
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

local function UpdateVisuals(frame, event, updateInfo)
    local cfg = GroupSpec(frame)
    if not cfg then return end
    local spec = frame.MSUFSpec
    local needsSnapshot = NeedsAuraSnapshot(frame)
    local snapshot = needsSnapshot and AuraSnapshot(frame, cfg, spec) or nil
    local border = spec and spec.border
    local borderAuraEnabled = border and border.dispel == true
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

    UpdateTarget(frame, cfg)
    UpdateFocus(frame, cfg)
    UpdateHealthFade(frame, cfg)
    UpdateStripe(frame, cfg, snapshot)
    UpdateDispelOverlay(frame, cfg, snapshot, spec)

    -- Borders no longer owns UNIT_AURA. GroupVisuals computes the shared
    -- snapshot once, then pokes the border from here so aura + border never
    -- perform separate scans for the same frame/event.
    if event == "MSUF_GF_VISUALS_APPLY" or event == "MSUF_GF_RANGE_ALPHA" or event == "UNIT_AURA" or IsDispelCapabilityEvent(event) then
        local active = frame._msufActiveElements
        local borders = active and active.Borders == true and UF.elements and UF.elements.Borders
        if borders and borders.Update then
            borders.Update(frame, "MSUF_GF_VISUALS", frame.unit)
        end
    end
end

function GroupVisuals.Apply(frame) UpdateVisuals(frame, "MSUF_GF_VISUALS_APPLY") end
function GroupVisuals.Update(frame, event, unit, updateInfo) UpdateVisuals(frame, event, updateInfo) end

UF.RegisterElement("GroupVisuals", GroupVisuals)
