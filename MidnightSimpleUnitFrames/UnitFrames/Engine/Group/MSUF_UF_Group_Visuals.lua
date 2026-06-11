local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF

if not (UF and UF.RegisterElement) then return end

local CreateFrame = _G.CreateFrame

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
local UnitIsUnit = _G.UnitIsUnit
local UnitIsConnected = _G.UnitIsConnected
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local tonumber = tonumber
local type = type
local max = math.max
local floor = math.floor
local GetTime = _G.GetTime
local issecretvalue = _G.issecretvalue or function(_) return false end

local function IsUnitToken(unit)
    if issecretvalue(unit) == true then return false end
    return type(unit) == "string" and unit ~= ""
end

-- Event subscription lists. DeadBg is driven by UNIT_FLAGS (dead/ghost/res)
-- and UNIT_CONNECTION (offline) only; HealthFade is the only visual feature
-- that needs UNIT_HEALTH. This keeps DeadBg-only raid frames out of the
-- high-frequency health hotpath entirely.
local EMPTY_EVENTS = {}
local VISUAL_HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local VISUAL_HEALTH_FLAGS_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_FLAGS" }
local VISUAL_OFFLINE_EVENTS = { "UNIT_CONNECTION" }
local VISUAL_FLAGS_EVENTS = { "UNIT_FLAGS" }
local VISUAL_FLAGS_OFFLINE_EVENTS = { "UNIT_CONNECTION", "UNIT_FLAGS" }
local VISUAL_HEALTH_OFFLINE_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" }
local EDGE_KEYS = { "top", "bottom", "left", "right" }
local HEALTH_FADE_SECRET_THROTTLE = 0.1

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
    if issecretvalue(r) == true or issecretvalue(g) == true
        or issecretvalue(b) == true or issecretvalue(a) == true then
        tex:SetColorTexture(r, g, b, a)
        tex._msufGFVisualTextureKind = nil
        tex._msufGFVisualTexture = nil
        tex._msufGFVisualColorR = nil
        tex._msufGFVisualColorG = nil
        tex._msufGFVisualColorB = nil
        tex._msufGFVisualColorA = nil
        return
    end
    if issecretvalue(tex._msufGFVisualColorR) == true
        or issecretvalue(tex._msufGFVisualColorG) == true
        or issecretvalue(tex._msufGFVisualColorB) == true
        or issecretvalue(tex._msufGFVisualColorA) == true then
        tex._msufGFVisualTextureKind = nil
        tex._msufGFVisualColorR = nil
        tex._msufGFVisualColorG = nil
        tex._msufGFVisualColorB = nil
        tex._msufGFVisualColorA = nil
    end
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

local function SameUnit(unit, otherUnit)
    if not (IsUnitToken(unit) and IsUnitToken(otherUnit)) then
        return false
    end
    if unit == otherUnit then
        return true
    end
    if UnitIsUnit then
        local same = UnitIsUnit(unit, otherUnit)
        if issecretvalue(same) == true then
            return false
        end
        return same == true or same == 1
    end
    if not UnitGUID then
        return false
    end
    local guid = UnitGUID(unit)
    local otherGuid = UnitGUID(otherUnit)
    if issecretvalue(guid) == true or issecretvalue(otherGuid) == true then
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
    if not cfg then
        SetEdgesShown(frame and frame.MSUFGFTargetEdges, false)
        return
    end
    local show = cfg.targetIndicator == true and frame.unit and SameUnit(frame.unit, "target") or false
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
    if not cfg then
        SetEdgesShown(frame and frame.MSUFGFFocusEdges, false)
        return
    end
    local show = cfg.focusIndicator == true and frame.unit and SameUnit(frame.unit, "focus") or false
    SetEdgesShown(frame.MSUFGFFocusEdges, show)
end

local function AuraVisualTarget(frame, onHealth)
    if onHealth ~= false then
        return frame and (frame.hpBar or frame.Health or frame.health) or frame
    end
    return frame
end

local function LayoutAuraVisual(tex, target, edge, size)
    if not (tex and target) then return end
    edge = edge or "FULL"
    if edge ~= "TOP" and edge ~= "BOTTOM" and edge ~= "LEFT" and edge ~= "RIGHT" then
        edge = "FULL"
    end
    size = max(1, floor((tonumber(size) or 3) + 0.5))
    if tex._msufGFVisualTarget == target
        and tex._msufGFVisualEdge == edge
        and tex._msufGFVisualSize == size then
        return
    end
    tex:ClearAllPoints()
    if edge == "FULL" then
        tex:SetAllPoints(target)
    elseif edge == "TOP" then
        tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        tex:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        SetHeightCached(tex, size, "_msufGFAuraVisualHeight")
    elseif edge == "BOTTOM" then
        tex:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        SetHeightCached(tex, size, "_msufGFAuraVisualHeight")
    elseif edge == "LEFT" then
        tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        tex:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        SetWidthCached(tex, size, "_msufGFAuraVisualWidth")
    else
        tex:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        SetWidthCached(tex, size, "_msufGFAuraVisualWidth")
    end
    tex._msufGFVisualTarget = target
    tex._msufGFVisualEdge = edge
    tex._msufGFVisualSize = size
end

local function EnsureAuraTexture(frame, key)
    local tex = frame and frame[key]
    if tex then return tex end
    if not frame then return nil end
    tex = frame:CreateTexture(nil, "OVERLAY", nil, 5)
    tex:SetColorTexture(1, 1, 1, 1)
    tex:Hide()
    frame[key] = tex
    return tex
end

local function UpdateDispelOverlay(frame, cfg)
    local tex = frame and frame.MSUFGFDispelOverlay
    if not (cfg and cfg.dispelOverlayEnabled == true and frame and frame._msufA3DispelOverlayActive == true) then
        SetShown(tex, false)
        return
    end
    tex = tex or EnsureAuraTexture(frame, "MSUFGFDispelOverlay")
    if not tex then return end
    local target = AuraVisualTarget(frame, cfg.dispelOverlayOnHealth)
    LayoutAuraVisual(tex, target, cfg.dispelOverlayStyle or "FULL", cfg.highlightThickness or 3)
    SetColorTextureCached(tex,
        frame._msufA3DispelOverlayR or frame._msufA3DispelR or 0.25,
        frame._msufA3DispelOverlayG or frame._msufA3DispelG or 0.75,
        frame._msufA3DispelOverlayB or frame._msufA3DispelB or 1,
        cfg.dispelOverlayAlpha or 0.35)
    SetShown(tex, true)
end

local function UpdateDebuffStripe(frame, cfg)
    local tex = frame and frame.MSUFGFDebuffStripe
    if not (cfg and cfg.debuffStripeEnabled == true and frame and frame._msufA3DebuffStripeActive == true) then
        SetShown(tex, false)
        return
    end
    tex = tex or EnsureAuraTexture(frame, "MSUFGFDebuffStripe")
    if not tex then return end
    local target = frame.hpBar or frame.Health or frame
    LayoutAuraVisual(tex, target, frame._msufA3DebuffStripeEdge or cfg.debuffStripeEdge or "BOTTOM",
        frame._msufA3DebuffStripeHeight or cfg.debuffStripeHeight or 3)
    SetColorTextureCached(tex,
        frame._msufA3DebuffStripeR or cfg.debuffStripeColorR or 0.8,
        frame._msufA3DebuffStripeG or cfg.debuffStripeColorG or 0.2,
        frame._msufA3DebuffStripeB or cfg.debuffStripeColorB or 0.2,
        frame._msufA3DebuffStripeA or cfg.debuffStripeAlpha or 0.6)
    SetShown(tex, true)
end

local function UpdateAuraVisuals(frame, cfg)
    UpdateDispelOverlay(frame, cfg)
    UpdateDebuffStripe(frame, cfg)
end

local indicatorDriver
local targetIndicatorCount = 0
local focusIndicatorCount = 0
local targetDriverRegistered
local focusDriverRegistered
local targetIndicatorFrames = {}
local targetIndicatorIndex = {}
local focusIndicatorFrames = {}
local focusIndicatorIndex = {}

local function RunIndicatorEvent(event)
    local list, update
    if event == "PLAYER_TARGET_CHANGED" then
        list, update = targetIndicatorFrames, UpdateTarget
    else
        list, update = focusIndicatorFrames, UpdateFocus
    end
    local live = GF and GF.frames
    for i = 1, #list do
        local frame = list[i]
        if frame and (not live or live[frame] == true) then
            local cfg = frame.MSUFSpec and frame.MSUFSpec.group
            update(frame, cfg)
        end
    end
end

local function IndicatorDriverOnEvent(_, event)
    RunIndicatorEvent(event)
end

local function EnsureIndicatorDriver()
    if indicatorDriver or not CreateFrame then
        return indicatorDriver
    end
    indicatorDriver = CreateFrame("Frame")
    indicatorDriver:SetScript("OnEvent", IndicatorDriverOnEvent)
    return indicatorDriver
end

local function RefreshIndicatorDriver()
    if not indicatorDriver and targetIndicatorCount <= 0 and focusIndicatorCount <= 0 then
        return
    end
    local driver = EnsureIndicatorDriver()
    if not driver then
        return
    end
    local wantTarget = targetIndicatorCount > 0
    if wantTarget ~= targetDriverRegistered then
        if wantTarget then
            driver:RegisterEvent("PLAYER_TARGET_CHANGED")
        else
            driver:UnregisterEvent("PLAYER_TARGET_CHANGED")
        end
        targetDriverRegistered = wantTarget
    end
    local wantFocus = focusIndicatorCount > 0
    if wantFocus ~= focusDriverRegistered then
        if wantFocus then
            driver:RegisterEvent("PLAYER_FOCUS_CHANGED")
        else
            driver:UnregisterEvent("PLAYER_FOCUS_CHANGED")
        end
        focusDriverRegistered = wantFocus
    end
end

local function AddIndicatorFrame(list, index, frame)
    if not frame or index[frame] then
        return
    end
    local n = #list + 1
    list[n] = frame
    index[frame] = n
end

local function RemoveIndicatorFrame(list, index, frame)
    local i = frame and index[frame]
    if not i then
        return
    end
    local last = #list
    local tail = list[last]
    list[i] = tail
    list[last] = nil
    index[frame] = nil
    if tail and tail ~= frame then
        index[tail] = i
    end
end

local function SetIndicatorRegistration(frame, target, focus)
    if not frame then
        return
    end
    target = target == true
    focus = focus == true
    local hadTarget = frame._msufGFTargetIndicatorRegistered == true
    if hadTarget ~= target then
        targetIndicatorCount = targetIndicatorCount + (target and 1 or -1)
        if targetIndicatorCount < 0 then targetIndicatorCount = 0 end
        frame._msufGFTargetIndicatorRegistered = target or nil
        if target then
            AddIndicatorFrame(targetIndicatorFrames, targetIndicatorIndex, frame)
        else
            RemoveIndicatorFrame(targetIndicatorFrames, targetIndicatorIndex, frame)
        end
    end
    local hadFocus = frame._msufGFFocusIndicatorRegistered == true
    if hadFocus ~= focus then
        focusIndicatorCount = focusIndicatorCount + (focus and 1 or -1)
        if focusIndicatorCount < 0 then focusIndicatorCount = 0 end
        frame._msufGFFocusIndicatorRegistered = focus or nil
        if focus then
            AddIndicatorFrame(focusIndicatorFrames, focusIndicatorIndex, frame)
        else
            RemoveIndicatorFrame(focusIndicatorFrames, focusIndicatorIndex, frame)
        end
    end
    RefreshIndicatorDriver()
end

local function PercentFromValues(hp, maxHP)
    if issecretvalue(hp) == true or hp == nil then
        return nil
    end
    if issecretvalue(maxHP) == true or maxHP == nil then
        return nil
    end
    if type(hp) ~= "number" then
        hp = tonumber(hp)
    end
    if type(maxHP) ~= "number" then
        maxHP = tonumber(maxHP)
    end
    if hp and maxHP and maxHP > 0 then
        return (hp / maxHP) * 100
    end
    return nil
end

local function CachedHealthValues(frame)
    local unit = frame and frame.unit
    local bar = frame and (frame.hpBar or frame.Health)
    if not (unit and bar) then
        return nil, nil
    end
    local hp = bar._msufHealthValueUnit == unit and bar._msufHealthValue or nil
    local maxHP = bar._msufHealthMaxUnit == unit and bar._msufHealthMax or nil
    return hp, maxHP
end

-- Health-percent fade (dim the bar near full HP) and group range fade, applied as a
-- multiplier on the hpBar object. The configured HP-fill opacity (hpBarAlpha) is owned
-- by the unified Alpha element (which sets the bar's fill texture), and the background
-- opacity (hpBgAlpha) is baked into the background colour -- both compose on top of the
-- multiplier set here.
local function UpdateHealthFade(frame, cfg, seedHP, seedMaxHP, event)
    if not frame.hpBar then return end
    local rangeAlpha = frame._msufGFRangeHealthAlpha or 1
    local keyHP, keyMax = seedHP, seedMaxHP
    local seedHPSecret = issecretvalue(seedHP) == true
    local seedMaxSecret = issecretvalue(seedMaxHP) == true
    local keyHPSecret = seedHPSecret
    local keyMaxSecret = seedMaxSecret
    local keyCacheable = keyHP ~= nil
        and keyMax ~= nil
        and not keyHPSecret
        and not keyMaxSecret
    if not keyCacheable then
        keyHP, keyMax = CachedHealthValues(frame)
        keyHPSecret = issecretvalue(keyHP) == true
        keyMaxSecret = issecretvalue(keyMax) == true
        keyCacheable = keyHP ~= nil
            and keyMax ~= nil
            and not keyHPSecret
            and not keyMaxSecret
    end
    if not keyCacheable and event == "UNIT_HEALTH" and GetTime then
        local now = GetTime()
        local nextAt = frame._msufGFHealthFadeSecretNextAt
        if frame._msufGFHealthFadeSecretRangeAlpha == rangeAlpha
            and frame._msufGFVisualHealthAlpha ~= nil
            and nextAt
            and now < nextAt then
            return
        end
        frame._msufGFHealthFadeSecretNextAt = now + HEALTH_FADE_SECRET_THROTTLE
        frame._msufGFHealthFadeSecretRangeAlpha = rangeAlpha
    end
    if keyCacheable
        and frame._msufGFHealthFadeSeedHP == keyHP
        and frame._msufGFHealthFadeSeedMax == keyMax
        and frame._msufGFHealthFadeRangeAlpha == rangeAlpha then
        return
    end

    local alpha = 1
    if cfg.healthFadeEnabled == true and frame.unit then
        local pct = PercentFromValues(keyHP, keyMax)
        if pct == nil and UnitHealthPercent then
            local raw = UnitHealthPercent(frame.unit)
            if issecretvalue(raw) ~= true then
                pct = tonumber(raw)
            end
        end
        if pct == nil
            and not seedHPSecret and seedHP == nil
            and not seedMaxSecret and seedMaxHP == nil
            and UnitHealth and UnitHealthMax then
            local hp, maxHP = UnitHealth(frame.unit), UnitHealthMax(frame.unit)
            pct = PercentFromValues(hp, maxHP)
        end
        if pct and pct >= (cfg.runtimeHealthFadeThreshold or cfg.healthFadeThreshold or 95) then
            alpha = alpha * (cfg.runtimeHealthFadeAlpha or cfg.healthFadeAlpha or 0.45)
        end
    end
    alpha = alpha * rangeAlpha
    if keyCacheable then
        frame._msufGFHealthFadeSeedHP = keyHP
        frame._msufGFHealthFadeSeedMax = keyMax
        frame._msufGFHealthFadeRangeAlpha = rangeAlpha
        frame._msufGFHealthFadeSecretNextAt = nil
        frame._msufGFHealthFadeSecretRangeAlpha = nil
    else
        frame._msufGFHealthFadeSeedHP = nil
        frame._msufGFHealthFadeSeedMax = nil
        frame._msufGFHealthFadeRangeAlpha = nil
    end
    if frame._msufGFVisualHealthAlpha == alpha then
        return
    end
    SetAlphaCached(frame.hpBar, alpha, "_msufGFVisualHealthAlpha")
    frame._msufGFVisualHealthAlpha = alpha
end

-- Dead / ghost / offline background tint. Resolved lazily through the shared bar
-- helpers so this file stays decoupled from BarsCommon load order (the helpers
-- are only ever needed at event time, long after every element file has loaded).
local BarTextCommon
local function BarHelper(name)
    BarTextCommon = BarTextCommon or MSUF.UFBarTextCommon
    return BarTextCommon and BarTextCommon[name]
end

local function ApplyDeadBgColor(region, texture, r, g, b, a)
    local fn = BarHelper("ApplyTextureColor")
    if fn then fn(region, texture, r, g, b, a) end
end

local function RestoreHealthBackground(frame)
    -- Transitioned back to alive/online. Cold-path group frames freeze their
    -- foreground colour after the first health tick and never register the
    -- UNIT_FLAGS/UNIT_CONNECTION events that would recolour it, so on resurrect
    -- the bar fill (and, with backgroundMatchHealth, the matched background) can
    -- stay stuck on the dead/offline grey -- only a /reload fixed it. Drive the
    -- Health element with a non-health reason so it re-reads the now-fresh unit
    -- state and recolours the fill from scratch. This runs only on the rare
    -- gone->alive edge, never on a health tick.
    local element = UF.elements and UF.elements.Health
    local active = frame and frame._msufActiveElements
    local unit = frame and frame.unit
    if element and element.Update and active and active.Health == true and IsUnitToken(unit) then
        local bar = frame.hpBar
        if bar then
            -- Force the cold-path recolour branch (updateColor keys off a nil
            -- cached status colour) and drop the stale RefreshUnitState cache so
            -- the dead/connected flags are re-probed.
            bar._msufStatusR = nil
            if frame._msufUnitState then frame._msufUnitState.ready = nil end
        end
        element.Update(frame, "MSUF_GF_VISUALS", unit)
    end
    -- Re-apply the configured health background. Health.Update only touches the
    -- background on the dynamic (backgroundMatchHealth) path, so a static
    -- background still wears the dead tint until this restores it. The helper is
    -- idempotent and cache-gated, so it is a no-op when already correct.
    local fn = BarHelper("ApplyBackgrounds")
    if fn then fn(frame, true, false) end
end

local function DispatchToken(frame)
    return frame and frame._msufDispatchActive == true and frame._msufDispatchToken or nil
end

local function ReadConnectedCached(frame, unit)
    local token = DispatchToken(frame)
    if token
        and frame._msufGFConnectedToken == token
        and frame._msufGFConnectedUnit == unit then
        return frame._msufGFConnectedValue, frame._msufGFConnectedKnown
    end
    if not UnitIsConnected then
        return true, true
    end
    local connected = UnitIsConnected(unit)
    if issecretvalue(connected) == true or connected == nil then
        if token then
            frame._msufGFConnectedToken = token
            frame._msufGFConnectedUnit = unit
            frame._msufGFConnectedValue = true
            frame._msufGFConnectedKnown = false
        end
        return true, false
    end
    connected = connected == true or connected == 1
    if token then
        frame._msufGFConnectedToken = token
        frame._msufGFConnectedUnit = unit
        frame._msufGFConnectedValue = connected
        frame._msufGFConnectedKnown = true
    end
    return connected, true
end

local function ReadDeadCached(frame, unit)
    local token = DispatchToken(frame)
    if token
        and frame._msufGFDeadToken == token
        and frame._msufGFDeadUnit == unit then
        return frame._msufGFDeadValue, frame._msufGFDeadKnown
    end
    if not UnitIsDeadOrGhost then
        return false, true
    end
    local dead = UnitIsDeadOrGhost(unit)
    if issecretvalue(dead) == true or dead == nil then
        if token then
            frame._msufGFDeadToken = token
            frame._msufGFDeadUnit = unit
            frame._msufGFDeadValue = false
            frame._msufGFDeadKnown = false
        end
        return false, false
    end
    dead = dead == true or dead == 1
    if token then
        frame._msufGFDeadToken = token
        frame._msufGFDeadUnit = unit
        frame._msufGFDeadValue = dead
        frame._msufGFDeadKnown = true
    end
    return dead, true
end

-- Returns true when the unit should wear the "gone" tint. Dead/ghost/resurrect
-- is resolved on UNIT_FLAGS and offline is resolved on UNIT_CONNECTION, keeping
-- DeadBg out of UNIT_HEALTH. If an explicit health-seeded update reaches this
-- helper, the seed still lets us answer without a unit API call.
local function ResolveGone(frame, cfg, unit, seedHP, event)
    local healthEvent = event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
    local state = frame and frame._msufUnitState
    local stateReady = state and state.ready == true and state.unit == unit
    local stateFresh = stateReady
        and frame._msufDispatchActive == true
        and state.dispatchToken == frame._msufDispatchToken
    local checkOffline = cfg.deadBgOffline == true
        and not healthEvent
        and (event ~= "UNIT_FLAGS" or frame._msufGFDeadBgState == true)
    if checkOffline and UnitIsConnected then
        if stateFresh and state.connectedKnown == true then
            if state.connected == false then
                return true
            end
        else
            local connected, known = ReadConnectedCached(frame, unit)
            if known == true and connected == false then
                return true
            end
        end
    end
    local deadKnown = stateFresh and state.deadKnown == true
    local dead = deadKnown and state.dead == true or false
    if dead then
        return true
    end
    local function UnitDeadOrGhost()
        if deadKnown then
            return false
        end
        local dg, known = ReadDeadCached(frame, unit)
        return known == true and dg == true
    end
    if issecretvalue(seedHP) ~= true and type(seedHP) == "number" then
        if seedHP == 0 then
            return true
        end
        -- hp > 0 on a health tick: alive, unless already wearing the ghost tint
        -- (UNIT_FLAGS set it). Stay tinted without an API call on health/max
        -- ticks; UNIT_FLAGS is what clears it on resurrect.
        if healthEvent and frame._msufGFDeadBgState == true then
            return true
        end
        if frame._msufGFDeadBgState == true and UnitDeadOrGhost() then
            return true
        end
        return false
    end
    if UnitDeadOrGhost() then
        return true
    end
    return false
end

local function UpdateDeadBg(frame, cfg, seedHP, event)
    local bg = frame.bg
    local unit = frame.unit
    if not (bg and unit) then return end
    local cached = frame._msufGFDeadBgState
    local gone = ResolveGone(frame, cfg, unit, seedHP, event)
    local firstResolve = cached == nil
    if gone then
        -- Fast path: already tinted and nothing can have overwritten frame.bg.
        -- A static background is only ever written by us, and cold-path group
        -- frames skip Health's colour update on the high-frequency UNIT_HEALTH
        -- tick, so a cached gone==true needs no work -- this keeps a ghost's HP
        -- ticks (hp > 0 keeps firing) at a single comparison. We only fall
        -- through to re-tint when the Health element shares this bg dynamically
        -- (backgroundMatchHealth / power match), where its grey dead-colour can
        -- clobber the tint, or on the first tint. A colour edit comes through
        -- GroupVisuals.Apply, which resets the cache, so it re-tints there.
        if cached == true and frame._msufHealthBgDynamic ~= true
            and frame._msufPowerBgDynamic ~= true then
            return
        end
        frame._msufGFDeadBgState = true
        local r, g, b = cfg.deadBgR or 0.6, cfg.deadBgG or 0.05, cfg.deadBgB or 0.05
        local a = cfg.deadBgA or 0.9
        local health = frame.MSUFSpec and frame.MSUFSpec.health
        local texture = health and health.backgroundTexture
        ApplyDeadBgColor(bg, texture, r, g, b, a)
        if frame.hpBarBG and frame.hpBarBG ~= bg then
            ApplyDeadBgColor(frame.hpBarBG, texture, r, g, b, a)
        end
        return
    end
    if cached == gone then return end
    frame._msufGFDeadBgState = gone
    if not firstResolve then
        -- Transitioned back to alive/online: hand the background back to the
        -- health element. On the first resolve the configured colour is already
        -- in place (Health.Apply ran moments earlier), so skip the redundant call.
        RestoreHealthBackground(frame)
    end
end

local HealthFadeActive

local function SpecNeedsGroupVisuals(spec)
    local cfg = spec and spec.group
    if not cfg then return false end
    return HealthFadeActive(cfg) == true
        or cfg.targetIndicator == true
        or cfg.focusIndicator == true
        or cfg.deadBgEnabled == true
        or cfg.dispelOverlayEnabled == true
        or cfg.debuffStripeEnabled == true
end

local UpdateBordersFromVisualState

HealthFadeActive = function(cfg)
    if not (cfg and cfg.healthFadeEnabled == true) then
        return false
    end
    local alpha = tonumber(cfg.runtimeHealthFadeAlpha or cfg.healthFadeAlpha)
    if alpha == nil then
        alpha = 0.45
    end
    return alpha < 1
end

local function RuntimeOnRangeAlpha(frame, cfg)
    UpdateHealthFade(frame, cfg, nil, nil, "MSUF_GF_RANGE_ALPHA")
    local active = frame and frame._msufActiveElements
    if active and active.Borders == true then
        UpdateBordersFromVisualState(frame)
    end
end

local function PrepareVisuals(frame, cfg)
    if not (frame and cfg) then return end
    PrepareTarget(frame, cfg)
    PrepareFocus(frame, cfg)
end

local function CompileVisualRuntime(spec)
    local cfg = spec and spec.group
    if cfg then
        cfg.runtimeHealthFadeThreshold = tonumber(cfg.healthFadeThreshold) or 95
        cfg.runtimeHealthFadeAlpha = tonumber(cfg.healthFadeAlpha) or 0.45
        cfg.runtimeOnHealth = HealthFadeActive(cfg) and UpdateHealthFade or nil
        cfg.runtimeOnTarget = cfg.targetIndicator == true and UpdateTarget or nil
        cfg.runtimeOnFocus = cfg.focusIndicator == true and UpdateFocus or nil
        cfg.runtimeOnDeadBg = cfg.deadBgEnabled == true and UpdateDeadBg or nil
        cfg.runtimeOnRangeAlpha = RuntimeOnRangeAlpha
        cfg.runtimeOnAuraVisuals = (cfg.dispelOverlayEnabled == true or cfg.debuffStripeEnabled == true) and UpdateAuraVisuals or nil
    end
end

local GroupVisuals = {}

function GroupVisuals.IsEnabled(frame, spec)
    return spec and spec.scope == "group" and SpecNeedsGroupVisuals(spec) == true
end

function GroupVisuals.GetEvents(frame, spec)
    local cfg = spec and spec.group
    if not cfg then return EMPTY_EVENTS end
    local health = HealthFadeActive(cfg)
    local offline = cfg.deadBgEnabled == true and cfg.deadBgOffline == true
    local flags = cfg.deadBgEnabled == true
    if health and offline then return VISUAL_HEALTH_OFFLINE_EVENTS end
    if health and flags then return VISUAL_HEALTH_FLAGS_EVENTS end
    if health then return VISUAL_HEALTH_EVENTS end
    if flags and offline then return VISUAL_FLAGS_OFFLINE_EVENTS end
    if flags then return VISUAL_FLAGS_EVENTS end
    if offline then return VISUAL_OFFLINE_EVENTS end
    return EMPTY_EVENTS
end

function GroupVisuals.GetUnitlessEvents(frame, spec)
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
            fn(frame, cfg, updateInfo, seedMaxHP, event)
        end
        return
    elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
        -- Connection toggles offline; UNIT_FLAGS fires on the dead/ghost/res
        -- transition. Both resolve DeadBg through the API fallback (seedHP nil).
        local fn = cfg.runtimeOnDeadBg
        if fn then
            fn(frame, cfg, nil, event)
        end
        return
    elseif event == "MSUF_GF_RANGE_ALPHA" then
        local fn = cfg.runtimeOnRangeAlpha
        if fn then
            fn(frame, cfg, event)
        end
        return
    elseif event == "MSUF_A3_AURA_VISUAL" then
        local fn = cfg.runtimeOnAuraVisuals
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
    if fn then fn(frame, cfg, updateInfo, seedMaxHP, event) end
    fn = cfg.runtimeOnDeadBg
    if fn then fn(frame, cfg, nil, event) end
    fn = cfg.runtimeOnAuraVisuals
    if fn then fn(frame, cfg, event) end

    if event == "MSUF_GF_VISUALS_APPLY" then
        UpdateBordersFromVisualState(frame)
    end
end

function GroupVisuals.UpdateHealthValue(frame, event, unit, seedHP, seedMaxHP)
    local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.group
    local fn = cfg and cfg.runtimeOnHealth
    if fn then
        fn(frame, cfg, seedHP, seedMaxHP, event)
    end
end

function GroupVisuals.UpdateGoneState(frame, event)
    local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.group
    local fn = cfg and cfg.runtimeOnDeadBg
    if fn then
        fn(frame, cfg, nil, event)
    end
end

function GroupVisuals.Apply(frame)
    -- Drop the cached dead/offline state: Health.Apply just restored the
    -- configured background, so the next resolve must re-tint from scratch (this
    -- also self-corrects a recycled frame that now holds a different unit).
    if frame then
        frame._msufGFDeadBgState = nil
        frame._msufGFHealthFadeSeedHP = nil
        frame._msufGFHealthFadeSeedMax = nil
        frame._msufGFHealthFadeRangeAlpha = nil
        frame._msufUpdateGroupVisualsHealthValue = GroupVisuals.UpdateHealthValue
        frame._msufUpdateGroupVisualsGoneState = GroupVisuals.UpdateGoneState
    end
    CompileVisualRuntime(frame and frame.MSUFSpec)
    local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.group
    SetIndicatorRegistration(frame, cfg and cfg.targetIndicator == true, cfg and cfg.focusIndicator == true)
    PrepareVisuals(frame, cfg)
    UpdateVisuals(frame, "MSUF_GF_VISUALS_APPLY")
end
function GroupVisuals.Update(frame, event, unit, updateInfo, seedMaxHP) UpdateVisuals(frame, event, updateInfo, seedMaxHP) end

function GroupVisuals.Disable(frame)
    if not frame then return end
    SetIndicatorRegistration(frame, false, false)
    HideEdges(frame.MSUFGFTargetEdges)
    HideEdges(frame.MSUFGFFocusEdges)
    SetShown(frame.MSUFGFDispelOverlay, false)
    SetShown(frame.MSUFGFDebuffStripe, false)
    if frame._msufGFDeadBgState == true then
        RestoreHealthBackground(frame)
    end
    frame._msufGFDeadBgState = nil
    frame._msufGFHealthFadeSeedHP = nil
    frame._msufGFHealthFadeSeedMax = nil
    frame._msufGFHealthFadeRangeAlpha = nil
    frame._msufUpdateGroupVisualsHealthValue = nil
    frame._msufUpdateGroupVisualsGoneState = nil
end

UF.RegisterElement("GroupVisuals", GroupVisuals)
