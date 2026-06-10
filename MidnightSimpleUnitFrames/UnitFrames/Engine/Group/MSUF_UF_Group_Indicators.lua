local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.RegisterElement) then return end

local function SetShown(region, show)
    if not region then return end
    show = show == true
    if region._msufGFShown == show then return end
    region:SetShown(show)
    region._msufGFShown = show
end
local UnitThreatSituation = UnitThreatSituation
local CreateFrame = CreateFrame
local tonumber = tonumber
local type = type
local pairs = pairs
local floor = math.floor
local max = math.max
local Secrets = MSUF.Secrets or {}
local UnitMissing = Secrets.UnitMissing or function(_) return false end
local issecretvalue = _G.issecretvalue or function(_) return false end
local Apply = MSUF.Apply or {}
local ApplyColorTexture = Apply.ColorTexture or function(tex, r, g, b, a)
    if not tex then return end
    a = a or 1
    if tex._aColorTexture ~= true or tex._aCTR ~= r or tex._aCTG ~= g
        or tex._aCTB ~= b or tex._aCTA ~= a then
        tex:SetColorTexture(r, g, b, a)
        tex._aColorTexture = true
        tex._aCTR = r
        tex._aCTG = g
        tex._aCTB = b
        tex._aCTA = a
        tex._aTex = nil
    end
end

local EMPTY = {}
local WHITE = "Interface\\Buttons\\WHITE8x8"
local CORNER_THREAT_EVENTS = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }

local function ClampLayer(layer, fallback)
    layer = floor((tonumber(layer) or fallback or 7) + 0.5)
    if layer < 0 then return 0 end
    if layer > 30 then return 30 end
    return layer
end

local function DrawSubLayer(layer, fallback)
    layer = ClampLayer(layer, fallback)
    if layer > 7 then return 7 end
    return layer
end

local function BaseFrameLevel(frame)
    local base = frame and (frame.hpBar or frame.Health or frame)
    return base and base.GetFrameLevel and (base:GetFrameLevel() or 0) or 0
end

local function EnsureHolder(frame, key, layer)
    frame.MSUFGFIndicatorHolders = frame.MSUFGFIndicatorHolders or {}
    local layerKey = key .. ":" .. ClampLayer(layer, 7)
    local holder = frame.MSUFGFIndicatorHolders[layerKey]
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        holder:EnableMouse(false)
        frame.MSUFGFIndicatorHolders[layerKey] = holder
    end
    local level = BaseFrameLevel(frame) + ClampLayer(layer, 7)
    if holder.SetFrameLevel and holder._msufGFLevel ~= level then
        holder:SetFrameLevel(level)
        holder._msufGFLevel = level
    end
    return holder
end

local function SetAllPointsCached(region, target)
    if not region then return end
    target = target or true
    if region._msufGFAllPointsTarget == target then
        return
    end
    region:ClearAllPoints()
    if target == true then
        region:SetAllPoints()
    else
        region:SetAllPoints(target)
    end
    region._msufGFAllPointsTarget = target
end

local function SetPointCached(region, point, relativeTo, relativePoint, x, y)
    x, y = x or 0, y or 0
    relativePoint = relativePoint or point
    if region._msufGFPoint == point and region._msufGFRel == relativeTo
        and region._msufGFRelPoint == relativePoint and region._msufGFX == x and region._msufGFY == y then
        return
    end
    region._msufGFPoint, region._msufGFRel, region._msufGFRelPoint = point, relativeTo, relativePoint
    region._msufGFX, region._msufGFY = x, y
    region:ClearAllPoints()
    region:SetPoint(point, relativeTo, relativePoint, x, y)
end

local function SetSizeCached(region, w, h)
    h = h or w
    if region._msufGFW == w and region._msufGFH == h then return end
    region._msufGFW, region._msufGFH = w, h
    region:SetSize(w, h)
end

local function SetColorTextureCached(tex, r, g, b, a)
    ApplyColorTexture(tex, r, g, b, a)
end

local function HasThreat(unit)
    if not UnitThreatSituation or not unit then return false end
    local status = UnitThreatSituation(unit)
    if issecretvalue(status) == true or status == nil then return false end
    status = tonumber(status)
    return status ~= nil and status >= 1
end

local GroupCornerIndicators = {}

function GroupCornerIndicators.IsEnabled(frame, spec)
    return spec and spec.scope == "group" and spec.cornerIndicators
        and spec.cornerIndicators.enabled == true and spec.cornerIndicators.hasWork == true
end

function GroupCornerIndicators.GetEvents(frame, spec)
    local cfg = spec and spec.cornerIndicators
    if cfg and cfg.needsThreat == true and cfg.needsAura ~= true then return CORNER_THREAT_EVENTS end
    if cfg and cfg.needsThreat == true then return CORNER_THREAT_EVENTS end
    return EMPTY
end

local function EnsureCorner(frame, key, layer)
    local holder = EnsureHolder(frame, "corner", layer)
    frame.MSUFGFCornerIndicators = frame.MSUFGFCornerIndicators or {}
    local tex = frame.MSUFGFCornerIndicators[key]
    local sub = DrawSubLayer(layer, 7)
    if not tex or tex:GetParent() ~= holder then
        if tex then tex:Hide() end
        tex = holder:CreateTexture(nil, "OVERLAY", nil, sub)
        frame.MSUFGFCornerIndicators[key] = tex
    elseif tex._msufGFLayer ~= sub and tex.SetDrawLayer then
        tex:SetDrawLayer("OVERLAY", sub)
    end
    tex._msufGFLayer = sub
    return tex, holder
end

local function HideCorners(frame)
    if frame and frame.MSUFGFCornerIndicators then
        for _, tex in pairs(frame.MSUFGFCornerIndicators) do SetShown(tex, false) end
    end
    if frame then
        frame._msufGFCornerThreatState = nil
        frame._msufGFCornerThreatCfg = nil
        frame._msufGFCornerPreparedCfg = nil
    end
end

local function PrepareCornerIndicators(frame, cfg)
    if not (frame and cfg and cfg.enabled == true) then return end
    local slots = cfg.aggroSlots or cfg.slots or EMPTY
    for i = 1, #slots do
        local slot = slots[i]
        if slot.category == "aggro" then
            local tex, holder = EnsureCorner(frame, slot.key, cfg.layer)
            local size = max(1, tonumber(cfg.size) or 8)
            SetSizeCached(tex, size, size)
            SetColorTextureCached(tex, cfg.aggroR or 1, cfg.aggroG or 0.55, cfg.aggroB or 0, cfg.alpha or 1)
            SetPointCached(tex, slot.anchor or "CENTER", holder, slot.anchor or "CENTER", slot.x or 0, slot.y or 0)
            SetShown(tex, false)
        end
    end
    if slots ~= cfg.slots and frame.MSUFGFCornerIndicators then
        for key, tex in pairs(frame.MSUFGFCornerIndicators) do
            if not (cfg.slotMap and cfg.slotMap[key] and cfg.slotMap[key].category == "aggro") then
                SetShown(tex, false)
            end
        end
    end
    frame._msufGFCornerPreparedCfg = cfg
end

local function SetThreatSlotsShown(frame, cfg, shown)
    local slots = cfg and cfg.aggroSlots or EMPTY
    local corners = frame and frame.MSUFGFCornerIndicators
    if not corners then return end
    for i = 1, #slots do
        local slot = slots[i]
        SetShown(corners[slot.key], shown)
    end
end

local function RuntimeThreat(frame, cfg, event)
    if not (frame and cfg and cfg.enabled == true and cfg.needsThreat == true) then return end
    local unit = frame.unit
    if unit and UnitMissing(unit) then
        frame._msufGFCornerThreatCfg = cfg
        frame._msufGFCornerThreatState = false
        SetThreatSlotsShown(frame, cfg, false)
        return
    end
    if frame._msufGFCornerPreparedCfg ~= cfg then return end
    local threat = HasThreat(unit)
    if (event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE")
        and frame._msufGFCornerThreatCfg == cfg
        and frame._msufGFCornerThreatState == threat then
        return
    end
    frame._msufGFCornerThreatCfg = cfg
    frame._msufGFCornerThreatState = threat
    SetThreatSlotsShown(frame, cfg, threat)
end

local function UpdateCornerIndicators(frame, event)
    local cfg = frame.MSUFSpec and frame.MSUFSpec.cornerIndicators
    if not (cfg and cfg.enabled == true) then HideCorners(frame); return end
    local fn = cfg.runtimeThreat
    if fn then
        return fn(frame, cfg, event)
    end
end

function GroupCornerIndicators.Apply(frame)
    local cfg = frame.MSUFSpec and frame.MSUFSpec.cornerIndicators
    if not (cfg and cfg.enabled == true) then HideCorners(frame); return end
    cfg.runtimeThreat = cfg.needsThreat == true and RuntimeThreat or nil
    PrepareCornerIndicators(frame, cfg)
    if cfg.runtimeThreat then
        cfg.runtimeThreat(frame, cfg, "MSUF_APPLY")
    end
end
function GroupCornerIndicators.Update(frame, event) UpdateCornerIndicators(frame, event) end
function GroupCornerIndicators.Disable(frame) HideCorners(frame) end

UF.RegisterElement("GroupCornerIndicators", GroupCornerIndicators)

GF.CI_SLOT_KEYS = { "TL", "TR", "BL", "BR", "C" }
GF.CI_CATEGORIES = {
    { key = "none", value = "none", label = "None", text = "None" },
    { key = "dispel", value = "dispel", label = "Dispellable", text = "Dispellable" },
    { key = "aggro", value = "aggro", label = "Aggro/Threat", text = "Aggro/Threat" },
    { key = "custom", value = "custom", label = "Custom Spell", text = "Custom Spell" },
}
GF.CI_CUSTOM_FILTERS = {
    { key = "HELPFUL|PLAYER", value = "HELPFUL|PLAYER", label = "Buff (cast by me)", text = "Buff (cast by me)", secretSafe = true },
    { key = "HELPFUL", value = "HELPFUL", label = "Buff (any caster)", text = "Buff (any caster)", secretSafe = false },
    { key = "HARMFUL|PLAYER", value = "HARMFUL|PLAYER", label = "Debuff (cast by me)", text = "Debuff (cast by me)", secretSafe = true },
    { key = "HARMFUL", value = "HARMFUL", label = "Debuff (any caster)", text = "Debuff (any caster)", secretSafe = false },
}
GF.CI_CUSTOM_MODES = {
    { key = "present", value = "present", label = "Show when present", text = "Show when present" },
    { key = "missing", value = "missing", label = "Show when missing", text = "Show when missing" },
}
