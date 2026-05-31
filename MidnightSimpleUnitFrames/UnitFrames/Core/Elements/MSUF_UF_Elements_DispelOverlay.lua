local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local V = MSUF.UFVisuals or {}
local UF = V.UF or MSUF.UF
local CreateFrame = V.CreateFrame or CreateFrame
local tonumber = V.tonumber or tonumber
local type = V.type or type
local max = V.max or math.max
local floor = V.floor or math.floor
local DispelState = V.DispelState or (UF and UF.DispelState) or {}
local BORDER_AURA_EVENTS = V.BORDER_AURA_EVENTS or { "UNIT_AURA" }
local DISPEL_CAPABILITY_EVENTS = V.DISPEL_CAPABILITY_EVENTS or {
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "SPELLS_CHANGED",
}
local IsDispelCapabilityEvent = V.IsDispelCapabilityEvent or function(event)
    return event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "SPELLS_CHANGED"
end
local MEDIA_ROOT = V.MEDIA_ROOT or ("Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\")
local DISPEL_OVERLAY_TEXTURES = V.DISPEL_OVERLAY_TEXTURES or {
    TOP = MEDIA_ROOT .. "MSUF_Grad_V.tga",
    BOTTOM = MEDIA_ROOT .. "MSUF_Grad_V_Rev.tga",
    LEFT = MEDIA_ROOT .. "MSUF_Grad_H.tga",
    RIGHT = MEDIA_ROOT .. "MSUF_Grad_H_Rev.tga",
}
local SetShown = V.SetShown

local function UnitDispelRuntimeEnabled(spec)
    local a3 = MSUF and (MSUF.MSUF_Auras3 or _G.MSUF_Auras3)
    if not (a3 and type(a3.BackendEnabled) == "function" and a3.BackendEnabled() == true) then
        return false
    end
    if not spec or spec.scope == "group" then return false end
    local border = spec.border
    local overlay = spec.dispelOverlay
    return (border and border.dispel == true) or (overlay and overlay.enabled == true)
end

local function DispelTriggerNeedsCapability(trigger)
    trigger = DispelState.NormalizeOverlayTrigger and DispelState.NormalizeOverlayTrigger(trigger) or trigger
    return trigger == "BY_ME" or trigger == "BORDER"
end

local function UnitDispelNeedsCapability(spec)
    local border = spec and spec.border
    local overlay = spec and spec.dispelOverlay
    if border and border.dispel == true and DispelTriggerNeedsCapability(border.dispelTrigger or "BY_ME") then
        return true
    end
    if overlay and overlay.enabled == true then
        local trigger = overlay.trigger or "BORDER"
        if trigger == "BORDER" then
            if not border or border.dispel ~= true then return true end
            return DispelTriggerNeedsCapability(border.dispelTrigger or "BY_ME")
        end
        return DispelTriggerNeedsCapability(trigger)
    end
    return false
end

local function DispelTriggerNeeds(trigger, needs)
    trigger = DispelState.NormalizeOverlayTrigger and DispelState.NormalizeOverlayTrigger(trigger) or trigger
    if trigger == "ANY_DEBUFF" then
        needs.needAnyDebuff = true
    elseif trigger == "DISPEL_TYPE" then
        needs.needAnyDispelType = true
    elseif trigger == "PLAYER_CAST" then
        needs.needPlayerCast = true
    else
        needs.needDispellable = true
    end
end

local function ResetUnitDispelState(frame, borderEnabled)
    frame._msufUFBorderAuraStateKnown = true
    frame._msufUFBorderAuraEnabled = borderEnabled == true
    frame._msufUFBorderAuraState = nil
    frame._msufUFBorderAuraColorR = nil
    frame._msufUFBorderAuraColorG = nil
    frame._msufUFBorderAuraColorB = nil
    frame._msufUFBorderAuraColorA = nil
    frame._msufUFDispelOverlayActive = false
    frame._msufUFDispelOverlayR = nil
    frame._msufUFDispelOverlayG = nil
    frame._msufUFDispelOverlayB = nil
    frame._msufUFDispelOverlayA = nil
end

local function UpdateUnitDispelState(frame, spec)
    local border = spec and spec.border
    local overlay = spec and spec.dispelOverlay
    local borderEnabled = border and border.dispel == true
    ResetUnitDispelState(frame, borderEnabled)
    if not (DispelState and DispelState.Update and UnitDispelRuntimeEnabled(spec)) then
        return nil
    end

    local needs = frame._msufUFDispelNeeds
    if not needs then
        needs = {}
        frame._msufUFDispelNeeds = needs
    end
    needs.needAnyDebuff = false
    needs.needAnyDispelType = false
    needs.needDispellable = false
    needs.needPlayerCast = false

    if borderEnabled then
        DispelTriggerNeeds(border.dispelTrigger or "BY_ME", needs)
    end
    if overlay and overlay.enabled == true then
        local trigger = overlay.trigger or "BORDER"
        if trigger == "BORDER" and borderEnabled then
            DispelTriggerNeeds(border.dispelTrigger or "BY_ME", needs)
        else
            DispelTriggerNeeds(trigger, needs)
        end
    end

    local snapshot = DispelState.Update(frame, needs)
    if not snapshot then return nil end

    if borderEnabled then
        local trigger = border.dispelTrigger or "BY_ME"
        local active = DispelState.ActiveForTrigger(snapshot, trigger, false) == true
        frame._msufUFBorderAuraState = active and "dispel" or nil
        if active then
            frame._msufUFBorderAuraColorR, frame._msufUFBorderAuraColorG, frame._msufUFBorderAuraColorB, frame._msufUFBorderAuraColorA =
                DispelState.ColorForTrigger(snapshot, trigger, spec and spec.dispel, 1)
        end
    end

    if overlay and overlay.enabled == true then
        local trigger = overlay.trigger or "BORDER"
        local borderActive = frame._msufUFBorderAuraState == "dispel"
        local activeTrigger = trigger == "BORDER" and not borderEnabled and "BY_ME" or trigger
        local active = DispelState.ActiveForTrigger(snapshot, activeTrigger, borderActive) == true
        frame._msufUFDispelOverlayActive = active
        if active then
            local colorTrigger = trigger == "BORDER" and borderEnabled and (border and border.dispelTrigger or "BY_ME") or activeTrigger
            frame._msufUFDispelOverlayR, frame._msufUFDispelOverlayG, frame._msufUFDispelOverlayB, frame._msufUFDispelOverlayA =
                DispelState.ColorForTrigger(snapshot, colorTrigger, spec and spec.dispel, overlay.alpha or 0.35)
        end
    end

    return snapshot
end

local function HideDispelOverlays(frame, except)
    local tex = frame and frame.MSUFDispelOverlay
    if tex and tex ~= except then SetShown(tex, false) end
    tex = frame and frame.MSUFDispelOverlayFrame
    if tex and tex ~= except then SetShown(tex, false) end
    tex = frame and frame.MSUFDispelOverlayHealth
    if tex and tex ~= except then SetShown(tex, false) end
end

local function EnsureDispelOverlayLayer(frame)
    local layer = frame.MSUFDispelOverlayLayer
    if not layer then
        layer = CreateFrame("Frame", nil, frame)
        layer:SetAllPoints(frame)
        layer:EnableMouse(false)
        frame.MSUFDispelOverlayLayer = layer
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
    if cfg and cfg.onHealth ~= false and frame.hpBar and frame.hpBar.CreateTexture then
        return frame.hpBar, "MSUFDispelOverlayHealth"
    end
    return EnsureDispelOverlayLayer(frame), "MSUFDispelOverlayFrame"
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
    frame.MSUFDispelOverlay = tex
    HideDispelOverlays(frame, tex)
    return tex
end

local function DispelOverlayTarget(frame, cfg)
    if cfg and cfg.onHealth ~= false and frame.hpBar then
        return frame.hpBar
    end
    return frame
end

local function LayoutDispelOverlay(tex, frame, cfg)
    local target = DispelOverlayTarget(frame, cfg)
    local style = cfg and cfg.style or "FULL"
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

local function DispelOverlayAlpha(alpha, cfg, spec)
    alpha = tonumber(alpha) or tonumber(cfg and cfg.alpha) or 0.35
    if cfg and cfg.onHealth ~= false
        and (cfg.style or "FULL") == "FULL"
        and spec and spec.health and spec.health.mode == "dark"
        and alpha > 0.18 then
        return 0.18
    end
    return alpha
end

local function PaintDispelOverlay(tex, style, r, g, b, a)
    local texture = DISPEL_OVERLAY_TEXTURES[style or "FULL"]
    if texture then
        tex:SetTexture(texture)
        tex:SetVertexColor(r, g, b, a)
    else
        tex:SetColorTexture(r, g, b, a)
    end
end

local function UpdateDispelOverlayTexture(frame, spec)
    local cfg = spec and spec.dispelOverlay
    local tex = frame.MSUFDispelOverlay
    if not (cfg and cfg.enabled == true and frame._msufUFDispelOverlayActive == true) then
        HideDispelOverlays(frame)
        return
    end
    tex = EnsureDispelOverlay(frame, cfg)
    LayoutDispelOverlay(tex, frame, cfg)
    PaintDispelOverlay(tex, cfg.style,
        frame._msufUFDispelOverlayR or 0.25,
        frame._msufUFDispelOverlayG or 0.75,
        frame._msufUFDispelOverlayB or 1,
        DispelOverlayAlpha(frame._msufUFDispelOverlayA, cfg, spec))
    SetShown(tex, true)
end

local DispelOverlay = {}

function DispelOverlay.IsEnabled(frame, spec)
    return UnitDispelRuntimeEnabled(spec)
end

function DispelOverlay.GetEvents()
    return BORDER_AURA_EVENTS
end

function DispelOverlay.GetUnitlessEvents(frame, spec)
    return UnitDispelNeedsCapability(spec) and DISPEL_CAPABILITY_EVENTS or nil
end

function DispelOverlay.Apply(frame, spec)
    UpdateUnitDispelState(frame, spec)
    UpdateDispelOverlayTexture(frame, spec)
end

function DispelOverlay.Disable(frame)
    ResetUnitDispelState(frame, false)
    HideDispelOverlays(frame)
end

function DispelOverlay.Update(frame, event)
    local spec = frame and frame.MSUFSpec
    UpdateUnitDispelState(frame, spec)
    UpdateDispelOverlayTexture(frame, spec)
    local active = frame and frame._msufActiveElements
    local borders = active and active.Borders == true and UF.elements and UF.elements.Borders
    if borders and borders.Update then
        borders.Update(frame, IsDispelCapabilityEvent(event) and "MSUF_DISPEL_CAPABILITY" or "MSUF_DISPEL_STATE", frame.unit)
    end
end

UF.RegisterElement("DispelOverlay", DispelOverlay)

