local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF

if not (UF and UF.RegisterElement) then return end

local function SetShown(region, show)
    if not region then return end
    show = show == true
    if region._msufGFVisualShown == show then return end
    region:SetShown(show)
    region._msufGFVisualShown = show
end
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitHealthPercent = UnitHealthPercent
local UnitGUID = UnitGUID
local tonumber = tonumber
local max = math.max
local floor = math.floor
local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end
local IsNil = Secrets.IsNil or function(value) return value == nil end

local EMPTY_EVENTS = {}
local VISUAL_HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local VISUAL_TARGET_EVENT = { "PLAYER_TARGET_CHANGED" }
local VISUAL_FOCUS_EVENT = { "PLAYER_FOCUS_CHANGED" }
local VISUAL_TARGET_FOCUS_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED" }
local EDGE_KEYS = { "top", "bottom", "left", "right" }

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

local function SameUnitByGUID(unit, otherUnit)
    if not (unit and otherUnit and UnitGUID) then
        return false
    end
    if unit == otherUnit then
        return true
    end
    local guid = UnitGUID(unit)
    local otherGuid = UnitGUID(otherUnit)
    if IsSecret(guid) or IsSecret(otherGuid) then
        return false
    end
    return guid ~= nil and guid == otherGuid
end

local function SetEdgesShown(edges, shown)
    if not edges then return end
    for i = 1, #EDGE_KEYS do
        SetShown(edges[EDGE_KEYS[i]], shown)
    end
end

local function PrepareTarget(frame, cfg)
    if not (frame and cfg and cfg.targetIndicator == true) then
        HideEdges(frame and frame.MSUFGFTargetEdges)
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
        SetShown(edge, false)
    end
end

local function UpdateTarget(frame, cfg)
    local show = cfg.targetIndicator == true and frame.unit and SameUnitByGUID(frame.unit, "target") or false
    SetEdgesShown(frame.MSUFGFTargetEdges, show)
end

local function PrepareFocus(frame, cfg)
    if not (frame and cfg and cfg.focusIndicator == true) then
        HideEdges(frame and frame.MSUFGFFocusEdges)
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
        SetShown(edge, false)
    end
end

local function UpdateFocus(frame, cfg)
    local show = cfg.focusIndicator == true and frame.unit and SameUnitByGUID(frame.unit, "focus") or false
    SetEdgesShown(frame.MSUFGFFocusEdges, show)
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

local function SpecNeedsGroupVisuals(spec)
    local cfg = spec and spec.group
    if not cfg then return false end
    return cfg.healthFadeEnabled == true
        or cfg.targetIndicator == true
        or cfg.focusIndicator == true
end

local UpdateBordersFromVisualState

local function RuntimeOnRangeAlpha(frame, cfg)
    UpdateHealthFade(frame, cfg)
    UpdateBordersFromVisualState(frame)
end

local function PrepareVisuals(frame, cfg)
    if not (frame and cfg) then return end
    PrepareTarget(frame, cfg)
    PrepareFocus(frame, cfg)
end

local function CompileVisualRuntime(spec)
    local cfg = spec and spec.group
    if cfg then
        cfg.runtimeOnHealth = cfg.healthFadeEnabled == true and UpdateHealthFade or nil
        cfg.runtimeOnTarget = cfg.targetIndicator == true and UpdateTarget or nil
        cfg.runtimeOnFocus = cfg.focusIndicator == true and UpdateFocus or nil
        cfg.runtimeOnRangeAlpha = RuntimeOnRangeAlpha
    end
end

local GroupVisuals = {}

function GroupVisuals.IsEnabled(frame, spec)
    return spec and spec.scope == "group" and SpecNeedsGroupVisuals(spec) == true
end

function GroupVisuals.GetEvents(frame, spec)
    local cfg = spec and spec.group
    if not cfg then return EMPTY_EVENTS end
    local health = cfg.healthFadeEnabled == true
    if health then return VISUAL_HEALTH_EVENTS end
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

UpdateBordersFromVisualState = function(frame)
    local active = frame and frame._msufActiveElements
    local borders = active and active.Borders == true and UF.elements and UF.elements.Borders
    if borders and borders.Update then
        borders.Update(frame, "MSUF_GF_VISUALS", frame.unit)
    end
end

local function UpdateVisuals(frame, event, updateInfo, seedMaxHP)
    local spec = frame.MSUFSpec
    local cfg = spec and spec.group
    if not cfg then return end

    if event == "PLAYER_TARGET_CHANGED" then
        local fn = cfg.runtimeOnTarget
        if fn then
            fn(frame, cfg, event)
        end
        return
    elseif event == "PLAYER_FOCUS_CHANGED" then
        local fn = cfg.runtimeOnFocus
        if fn then
            fn(frame, cfg, event)
        end
        return
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local fn = cfg.runtimeOnHealth
        if fn then
            fn(frame, cfg, updateInfo, seedMaxHP)
        end
        return
    elseif event == "MSUF_GF_RANGE_ALPHA" then
        local fn = cfg.runtimeOnRangeAlpha
        if fn then
            fn(frame, cfg, event)
        end
        return
    end

    local fn = cfg.runtimeOnTarget
    if fn then fn(frame, cfg, event) end
    fn = cfg.runtimeOnFocus
    if fn then fn(frame, cfg, event) end
    fn = cfg.runtimeOnHealth
    if fn then fn(frame, cfg) end

    if event == "MSUF_GF_VISUALS_APPLY" then
        UpdateBordersFromVisualState(frame)
    end
end

function GroupVisuals.Apply(frame)
    CompileVisualRuntime(frame and frame.MSUFSpec)
    local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.group
    PrepareVisuals(frame, cfg)
    UpdateVisuals(frame, "MSUF_GF_VISUALS_APPLY")
end
function GroupVisuals.Update(frame, event, unit, updateInfo, seedMaxHP) UpdateVisuals(frame, event, updateInfo, seedMaxHP) end

function GroupVisuals.Disable(frame)
    if not frame then return end
    HideEdges(frame.MSUFGFTargetEdges)
    HideEdges(frame.MSUFGFFocusEdges)
end

UF.RegisterElement("GroupVisuals", GroupVisuals)
