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
local UnitIsConnected = _G.UnitIsConnected
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local tonumber = tonumber
local type = type
local max = math.max
local floor = math.floor
local issecretvalue = _G.issecretvalue or function(_) return false end

local function IsUnitToken(unit)
    return type(unit) == "string" and unit ~= ""
end

-- Event subscription lists. DeadBg adds UNIT_FLAGS so the rare dead<->ghost<->res
-- transition (which always raises UNIT_FLAGS) is what probes UnitIsDeadOrGhost --
-- the per-UNIT_HEALTH tick stays a single hp==0 comparison with no API call.
local EMPTY_EVENTS = {}
local VISUAL_HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local VISUAL_HEALTH_FLAGS_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_FLAGS" }
local VISUAL_OFFLINE_EVENTS = { "UNIT_CONNECTION" }
local VISUAL_HEALTH_OFFLINE_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" }
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
    if issecretvalue(hp) == true or hp == nil then
        return nil
    end
    if issecretvalue(maxHP) == true or maxHP == nil then
        return nil
    end
    hp, maxHP = tonumber(hp), tonumber(maxHP)
    if hp and maxHP and maxHP > 0 then
        return (hp / maxHP) * 100
    end
    return nil
end

-- Health-percent fade (dim the bar near full HP) and group range fade, applied as a
-- multiplier on the hpBar object. The configured HP-fill opacity (hpBarAlpha) is owned
-- by the unified Alpha element (which sets the bar's fill texture), and the background
-- opacity (hpBgAlpha) is baked into the background colour -- both compose on top of the
-- multiplier set here.
local function UpdateHealthFade(frame, cfg, seedHP, seedMaxHP)
    if not frame.hpBar then return end
    local alpha = 1
    if cfg.healthFadeEnabled == true and frame.unit then
        local pct = PercentFromValues(seedHP, seedMaxHP)
        if pct == nil and UnitHealthPercent then
            local raw = UnitHealthPercent(frame.unit)
            if issecretvalue(raw) ~= true then
                pct = tonumber(raw)
            end
        end
        if pct == nil
            and issecretvalue(seedHP) ~= true and seedHP == nil
            and issecretvalue(seedMaxHP) ~= true and seedMaxHP == nil
            and UnitHealth and UnitHealthMax then
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

-- Returns true when the unit should wear the "gone" tint. The hot UNIT_HEALTH
-- path never calls a unit API: a live unit reads hp > 0 and a dead one reads
-- hp == 0. Dead/ghost/resurrect always raises UNIT_FLAGS and offline raises
-- UNIT_CONNECTION -- those (seedHP nil) are where the rare API probes happen
-- (UnitIsDeadOrGhost / UnitIsConnected). A ghost has hp > 0, so the HP tick
-- alone cannot tell it from alive; the cached tint state carries it across
-- ticks until UNIT_FLAGS flips it back. Everything else is decided from the hp
-- value the dispatch already handed us.
local function ResolveGone(frame, cfg, unit, seedHP, event)
    local healthEvent = event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
    if cfg.deadBgOffline == true and not healthEvent and UnitIsConnected then
        local connected = UnitIsConnected(unit)
        if issecretvalue(connected) ~= true and (connected == false or connected == 0) then
            return true
        end
    end
    if issecretvalue(seedHP) ~= true and type(seedHP) == "number" then
        if seedHP == 0 then
            return true
        end
        -- hp > 0 on a health tick: alive, unless already wearing the ghost tint
        -- (UNIT_FLAGS set it). Stay tinted without an API call; UNIT_FLAGS is
        -- what clears it on resurrect.
        if frame._msufGFDeadBgState == true and UnitIsDeadOrGhost then
            local dg = UnitIsDeadOrGhost(unit)
            if issecretvalue(dg) ~= true and (dg == true or dg == 1) then
                return true
            end
        end
        return false
    end
    if UnitIsDeadOrGhost then
        local dg = UnitIsDeadOrGhost(unit)
        if issecretvalue(dg) ~= true and (dg == true or dg == 1) then
            return true
        end
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

local function SpecNeedsGroupVisuals(spec)
    local cfg = spec and spec.group
    if not cfg then return false end
    return cfg.healthFadeEnabled == true
        or cfg.targetIndicator == true
        or cfg.focusIndicator == true
        or cfg.deadBgEnabled == true
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
        cfg.runtimeOnDeadBg = cfg.deadBgEnabled == true and UpdateDeadBg or nil
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
    local health = cfg.healthFadeEnabled == true or cfg.deadBgEnabled == true
    local offline = cfg.deadBgEnabled == true and cfg.deadBgOffline == true
    -- DeadBg needs UNIT_FLAGS to catch the dead<->ghost<->resurrect transition
    -- (a ghost has hp > 0, so UNIT_HEALTH alone cannot tell it apart from alive).
    local flags = cfg.deadBgEnabled == true
    if health and offline then return VISUAL_HEALTH_OFFLINE_EVENTS end
    if health and flags then return VISUAL_HEALTH_FLAGS_EVENTS end
    if health then return VISUAL_HEALTH_EVENTS end
    if offline then return VISUAL_OFFLINE_EVENTS end
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
        fn = cfg.runtimeOnDeadBg
        if fn then
            fn(frame, cfg, updateInfo, event)
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
    end

    local fn = cfg.runtimeOnTarget
    if fn then fn(frame, cfg, event) end
    fn = cfg.runtimeOnFocus
    if fn then fn(frame, cfg, event) end
    fn = cfg.runtimeOnHealth
    if fn then fn(frame, cfg) end
    fn = cfg.runtimeOnDeadBg
    if fn then fn(frame, cfg, nil, event) end

    if event == "MSUF_GF_VISUALS_APPLY" then
        UpdateBordersFromVisualState(frame)
    end
end

function GroupVisuals.Apply(frame)
    -- Drop the cached dead/offline state: Health.Apply just restored the
    -- configured background, so the next resolve must re-tint from scratch (this
    -- also self-corrects a recycled frame that now holds a different unit).
    if frame then frame._msufGFDeadBgState = nil end
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
    if frame._msufGFDeadBgState == true then
        RestoreHealthBackground(frame)
    end
    frame._msufGFDeadBgState = nil
end

UF.RegisterElement("GroupVisuals", GroupVisuals)
