-- UF border element: applies border, outline, and dispel visuals from compiled specs.
-- Live updates must avoid secret payload comparisons and keep expensive scans outside hotpaths.
local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local V = MSUF.UFVisuals or {}
local UF = V.UF or MSUF.UF
local Layers = UF and UF.Layers or {}

-- Unitframe border overlay element.
-- Owns highlight, aggro, purge/dispel, and boss-target border layers for unitframes. Runtime
-- updates are event-driven and secret-safe; page code only changes DB/style inputs.
local CreateFrame = V.CreateFrame or CreateFrame
local UnitExists = V.UnitExists or UnitExists
local UnitIsUnit = V.UnitIsUnit or UnitIsUnit
local UnitThreatSituation = V.UnitThreatSituation or UnitThreatSituation
local UnitGroupRolesAssigned = V.UnitGroupRolesAssigned or UnitGroupRolesAssigned
local tonumber = V.tonumber or tonumber
local tostring = V.tostring or tostring
local type = V.type or type
local IsNil = V.IsNil or function(value) return value == nil end
local NotSecretValue = V.NotSecretValue or function(_) return true end
local IsSecretValue = _G.issecretvalue or function(_) return false end
local EMPTY_EVENTS = V.EMPTY_EVENTS or {}
local BORDER_THREAT_EVENTS = V.BORDER_THREAT_EVENTS or { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }
local TARGET_CHANGE_EVENTS = { "PLAYER_TARGET_CHANGED" }
local SetShown = V.SetShown
local ReadGroupThreatStatus = V.ReadGroupThreatStatus
local ReadGroupRole = V.ReadGroupRole
local FreshUnitState = UF and UF.FreshUnitState

local Borders = {}
local IsAggroBorderUnit
local IsBossUnit

function Borders.GetEvents(frame, spec)
  local cfg = spec and spec.border
  if not cfg then
    return EMPTY_EVENTS
  end
  if cfg.aggro == true and IsAggroBorderUnit(frame) then
    return BORDER_THREAT_EVENTS
  end
  return EMPTY_EVENTS
end

function Borders.GetUnitlessEvents(frame, spec)
  local cfg = spec and spec.border
  local unit = frame and frame.MSUFUnitKey
  -- The player-frame aggro query compares player against the current target.
  -- A target swap can therefore change the answer without producing a threat
  -- event for player; seed it explicitly from the target lifecycle event.
  if cfg and cfg.aggro == true and unit == "player" then
    return TARGET_CHANGE_EVENTS
  end
  if cfg and cfg.bossTarget == true and IsBossUnit(unit) then
    return TARGET_CHANGE_EVENTS
  end
  return EMPTY_EVENTS
end

local EDGE_KEYS = { "top", "bottom", "left", "right" }
local DEFAULT_HIGHLIGHT_PRIORITY = { "dispel", "aggro", "purge", "bossTarget" }
local BORDER_LEVEL_NORMAL = Layers.FRAME_BORDER_NORMAL_OFFSET or 35
local BORDER_LEVEL_DEFAULT = Layers.FRAME_BORDER_DEFAULT_OFFSET or 40
local BORDER_LEVEL_OVER_NATIVE_DISPEL = Layers.FRAME_BORDER_OVER_NATIVE_DISPEL_OFFSET or 50

local function EnsureBorderOverlay(parent)
  local overlay = parent.MSUFBorderOverlay
  if not overlay then
    overlay = CreateFrame("Frame", nil, parent)
    overlay:SetAllPoints(parent)
    overlay:EnableMouse(false)
    parent.MSUFBorderOverlay = overlay
  end
  if parent.GetFrameLevel and overlay.SetFrameLevel then
    local level = (parent:GetFrameLevel() or 1) + (parent._msufBorderLevelOffset or BORDER_LEVEL_DEFAULT)
    if overlay._msufBorderLevel ~= level then
      overlay:SetFrameLevel(level)
      overlay._msufBorderLevel = level
    end
  end
  return overlay
end

local function SetBorderOverlayStrata(frame, overlay, strata)
  if not (frame and overlay and overlay.SetFrameStrata) then return end
  if IsSecretValue(strata) then strata = nil end
  if strata == nil or strata == "" or strata == "AUTO" then
    strata = frame.GetFrameStrata and frame:GetFrameStrata() or nil
  end
  if IsSecretValue(strata) or strata == nil or strata == "" then return end
  local cachedStrata = overlay._msufBorderStrata
  local currentStrata
  if overlay.GetFrameStrata then currentStrata = overlay:GetFrameStrata() end
  if IsSecretValue(cachedStrata) or IsSecretValue(currentStrata) or cachedStrata ~= strata or currentStrata ~= strata then
    if IsSecretValue(currentStrata) or currentStrata ~= strata then
      overlay:SetFrameStrata(strata)
    end
    overlay._msufBorderStrata = strata
  end
end

local function SetBorderOverlayLevel(frame, offset, strata, layer)
  if not frame then return end
  -- `layer` is clamped by the cold config compiler. Runtime event updates only
  -- add the already-compiled value and never touch SavedVariables.
  offset = (offset or BORDER_LEVEL_DEFAULT) + (layer or 0)
  if frame._msufBorderLevelOffset ~= offset then
    frame._msufBorderLevelOffset = offset
    if frame.MSUFBorderOverlay then
      frame.MSUFBorderOverlay._msufBorderLevel = nil
    end
  end
  SetBorderOverlayStrata(frame, EnsureBorderOverlay(frame), strata)
end

local function EnsureEdge(parent, key)
  parent.MSUFBorderEdges = parent.MSUFBorderEdges or {}
  local overlay = EnsureBorderOverlay(parent)
  local edge = parent.MSUFBorderEdges[key]
  if edge and edge.GetParent and edge:GetParent() ~= overlay then
    edge:Hide()
    edge = nil
    parent.MSUFBorderEdges[key] = nil
  end
  if edge then
    return edge
  end
  edge = overlay:CreateTexture(nil, "OVERLAY")
  edge:SetColorTexture(0, 0, 0, 1)
  parent.MSUFBorderEdges[key] = edge
  return edge
end

local function LayoutBorder(frame, thickness)
  EnsureBorderOverlay(frame)
  thickness = tonumber(thickness) or 1
  if thickness < 1 then
    thickness = 1
  end
  local edges = frame.MSUFBorderEdges
  if frame._msufBorderThickness == thickness
    and frame._msufBorderLayoutReady == true
    and edges and edges.top and edges.bottom and edges.left and edges.right then
    return
  end
  local top = EnsureEdge(frame, "top")
  local bottom = EnsureEdge(frame, "bottom")
  local left = EnsureEdge(frame, "left")
  local right = EnsureEdge(frame, "right")
  top:ClearAllPoints()
  bottom:ClearAllPoints()
  left:ClearAllPoints()
  right:ClearAllPoints()
  top:SetPoint("TOPLEFT", frame, "TOPLEFT", -thickness, thickness)
  top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", thickness, thickness)
  top:SetHeight(thickness)
  bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -thickness, -thickness)
  bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", thickness, -thickness)
  bottom:SetHeight(thickness)
  left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
  left:SetWidth(thickness)
  right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
  right:SetWidth(thickness)
  frame._msufBorderThickness = thickness
  frame._msufBorderLayoutReady = true
end

local function BorderNormalEnabled(cfg)
  return cfg and cfg.enabled == true and (tonumber(cfg.thickness) or 0) > 0
end

function IsBossUnit(unit)
  if type(unit) ~= "string" or unit:sub(1, 4) ~= "boss" then return false end
  local index = tonumber(unit:sub(5))
  return index ~= nil and index >= 1 and index <= 5
end

function IsAggroBorderUnit(frame)
  local unit = frame and frame.MSUFUnitKey
  if unit == "player" or unit == "target" or unit == "focus" then return true end
  return IsBossUnit(unit)
    or (frame and (frame._msufBorderRuntimeGroup == true
      or frame._msufIsGroupFrame == true
      or frame._msufCoreScope == "group"))
end

local function IsPurgeBorderUnit(frame)
  local unit = frame and frame.MSUFUnitKey
  return unit == "target" or unit == "focus" or unit == "targettarget"
end

local function TestScopeApplies(frame, scope)
  if not frame then return false end
  scope = scope or "shared"
  if scope == "shared" then return true end
  local spec = frame.MSUFSpec
  local groupKind = frame._msufGFKind or spec and spec.groupKind
  if scope == "party" or scope == "gf_party" then
    return groupKind == "party"
  elseif scope == "raid" or scope == "gf_raid" then
    return groupKind == "raid" or groupKind == "mythicraid"
  elseif scope == "mythicraid" or scope == "gf_mythicraid" then
    return groupKind == "mythicraid"
  elseif groupKind then
    return false
  elseif scope == "boss" then
    return IsBossUnit(frame.MSUFUnitKey)
  end
  return frame.MSUFUnitKey == scope or frame.configKey == scope or frame.unitKey == scope
end

local function RefreshBorderTestFrames()
  if UF and UF.RefreshBorders then
    UF.RefreshBorders()
  end
  local gf = MSUF and MSUF.GF
  if gf then
    if gf.RefreshBorder then
      gf.RefreshBorder()
    elseif gf.RefreshVisuals then
      gf.RefreshVisuals(nil, gf.DIRTY_BORDER or gf.DIRTY_VISUAL)
    elseif gf.MarkAllDirty then
      gf.MarkAllDirty(gf.DIRTY_BORDER or gf.DIRTY_VISUAL or 2)
    end
  end
end

local function RefreshBorderTestModesActive()
  ExportPublic("MSUF_BorderTestModesActive", _G.MSUF_AggroBorderTestMode == true
    or _G.MSUF_DispelBorderTestMode == true
    or _G.MSUF_PurgeBorderTestMode == true
    or _G.MSUF_BossTargetBorderTestMode == true)
end

local function SetBorderTestMode(flag, scopeFlag, active, scope)
  _G[flag] = active == true
  if scopeFlag then _G[scopeFlag] = scope or "shared" end
  RefreshBorderTestModesActive()
  RefreshBorderTestFrames()
  return true
end

local SetAggroBorderTestMode = _G.MSUF_SetAggroBorderTestMode or function(active, scope)
  return SetBorderTestMode("MSUF_AggroBorderTestMode", "MSUF_AggroBorderTestScope", active, scope)
end
ExportPublic("MSUF_SetAggroBorderTestMode", SetAggroBorderTestMode)

local SetDispelBorderTestMode = _G.MSUF_SetDispelBorderTestMode or function(active, scope)
  return SetBorderTestMode("MSUF_DispelBorderTestMode", "MSUF_DispelBorderTestScope", active, scope)
end
ExportPublic("MSUF_SetDispelBorderTestMode", SetDispelBorderTestMode)

local SetPurgeBorderTestMode = _G.MSUF_SetPurgeBorderTestMode or function(active, scope)
  return SetBorderTestMode("MSUF_PurgeBorderTestMode", "MSUF_PurgeBorderTestScope", active, scope)
end
ExportPublic("MSUF_SetPurgeBorderTestMode", SetPurgeBorderTestMode)

local SetBossTargetBorderTestMode = _G.MSUF_SetBossTargetBorderTestMode or function(active)
  return SetBorderTestMode("MSUF_BossTargetBorderTestMode", nil, active, "boss")
end
ExportPublic("MSUF_SetBossTargetBorderTestMode", SetBossTargetBorderTestMode)

local function AggroTestApplies(frame)
  return _G.MSUF_BorderTestModesActive == true
    and _G.MSUF_AggroBorderTestMode == true
    and IsAggroBorderUnit(frame)
    and TestScopeApplies(frame, _G.MSUF_AggroBorderTestScope)
end

local function DispelTestApplies(frame)
  return _G.MSUF_BorderTestModesActive == true
    and _G.MSUF_DispelBorderTestMode == true
    and TestScopeApplies(frame, _G.MSUF_DispelBorderTestScope)
end

local function PurgeTestApplies(frame)
  return _G.MSUF_BorderTestModesActive == true
    and _G.MSUF_PurgeBorderTestMode == true
    and IsPurgeBorderUnit(frame)
    and TestScopeApplies(frame, _G.MSUF_PurgeBorderTestScope)
end

local function BossTargetTestApplies(frame)
  return _G.MSUF_BorderTestModesActive == true
    and _G.MSUF_BossTargetBorderTestMode == true
    and IsBossUnit(frame and frame.MSUFUnitKey)
end

local function BossTargetState(frame, cfg)
  if not (cfg and cfg.bossTarget == true and UnitIsUnit and frame and IsBossUnit(frame.MSUFUnitKey)) then
    return false
  end
  local isTarget = UnitIsUnit(frame.MSUFUnitKey, "target")
  if IsNil(isTarget) or not NotSecretValue(isTarget) then
    return false
  end
  return isTarget == true or isTarget == 1
end

local function BorderHighlightEnabled(frame, cfg)
  if cfg and cfg.aggro == true then
    return true
  end
  if cfg and cfg.dispel == true then
    return true
  end
  if cfg and cfg.bossTarget == true and IsBossUnit(frame and frame.MSUFUnitKey) then
    return true
  end
  if _G.MSUF_BorderTestModesActive ~= true then
    return false
  end
  return AggroTestApplies(frame)
    or DispelTestApplies(frame)
    or PurgeTestApplies(frame)
    or BossTargetTestApplies(frame)
end

local function BorderNormalThickness(cfg)
  local thickness = cfg and tonumber(cfg.thickness) or nil
  if not thickness or thickness < 1 then
    return 1
  end
  return thickness
end

local function BorderHighlightThickness(cfg)
  local thickness = cfg and tonumber(cfg.highlightThickness) or nil
  if not thickness or thickness < 1 then
    thickness = cfg and tonumber(cfg.thickness) or nil
  end
  if not thickness or thickness < 1 then
    return 1
  end
  return thickness
end

local function NormalizeAggroMode(mode)
  mode = tostring(mode or "ALL"):upper()
  if mode == "TANK_ONLY" then return "TANK" end
  if mode == "HEALER_ONLY" then return "HEALER" end
  return mode
end

local function SetBorder(frame, show, r, g, b, a)
  if not frame.MSUFBorderEdges then
    return
  end
  r, g, b, a = r or 0, g or 0, b or 0, a or 1
  local secretColor = IsSecretValue(r) or IsSecretValue(g) or IsSecretValue(b) or IsSecretValue(a)
  local showChanged = frame._msufBorderShown ~= show
  local colorChanged = secretColor == true
  if not colorChanged then
    if frame._msufBorderSecretColor == true then
      colorChanged = true
    else
      colorChanged = frame._msufBorderR ~= r
        or frame._msufBorderG ~= g
        or frame._msufBorderB ~= b
        or frame._msufBorderA ~= a
    end
  end
  if not (showChanged or colorChanged) then
    return
  end
  frame._msufBorderShown = show
  if secretColor then
    frame._msufBorderSecretColor = true
    frame._msufBorderR, frame._msufBorderG, frame._msufBorderB, frame._msufBorderA = nil, nil, nil, nil
  else
    frame._msufBorderSecretColor = nil
    frame._msufBorderR, frame._msufBorderG, frame._msufBorderB, frame._msufBorderA = r, g, b, a
  end
  for i = 1, #EDGE_KEYS do
    local edge = frame.MSUFBorderEdges[EDGE_KEYS[i]]
    if edge then
      if colorChanged then
        edge:SetVertexColor(1, 1, 1, 1)
        edge:SetColorTexture(r, g, b, a)
      end
      if showChanged then
        SetShown(edge, show)
      end
    end
  end
end

local function ThreatState(frame)
  if not (UnitThreatSituation and frame and frame.MSUFUnitKey) then
    return false
  end
  local unit = frame.MSUFUnitKey
  if frame._msufBorderRuntimeGroup == true
    or frame._msufIsGroupFrame == true
    or frame._msufCoreScope == "group" then
    local state = FreshUnitState and FreshUnitState(frame, unit) or nil
    if state and state.existsKnown == true then
      if state.exists ~= true then return false end
    else
      local exists = UnitExists and UnitExists(unit)
      if not IsNil(exists) and NotSecretValue(exists) and exists == false then
        return false
      end
    end
    local mode = frame._msufBorderRuntimeAggroMode
    if mode == nil then
      local spec = frame.MSUFSpec
      local cfg = spec and spec.border
      mode = NormalizeAggroMode(cfg and cfg.aggroMode)
    end
    if mode == "TANK" or mode == "HEALER" or mode == "NON_TANK" then
      local role
      if ReadGroupRole then
        role = ReadGroupRole(frame, unit)
      elseif UnitGroupRolesAssigned then
        role = UnitGroupRolesAssigned(unit)
      end
      if IsNil(role) or not NotSecretValue(role) then
        return false
      end
      if mode == "NON_TANK" then
        if role == "TANK" then
          return false
        end
      elseif role ~= mode then
        return false
      end
    end
    local status
    if ReadGroupThreatStatus then
      status = ReadGroupThreatStatus(frame, unit)
    else
      status = UnitThreatSituation(unit)
    end
    if IsNil(status) or not NotSecretValue(status) then
      return false
    end
    status = tonumber(status)
    return status ~= nil and status >= 1
  end

  local status
  if unit == "player" then
    status = UnitThreatSituation("player", "target")
    if IsNil(status) then
      status = UnitThreatSituation("player")
    end
  else
    status = UnitThreatSituation("player", unit)
  end
  if IsNil(status) or not NotSecretValue(status) then
    return false
  end
  status = tonumber(status)
  return status ~= nil and status >= 2
end

local function GeneralDB()
  local db = _G.MSUF_DB
  return db and db.general or nil
end

local function DispelTestColor(frame)
  local dispel = frame and frame.MSUFSpec and frame.MSUFSpec.dispel
  return dispel and dispel.r or 0.25, dispel and dispel.g or 0.75, dispel and dispel.b or 1, 1
end

local function AggroColor(cfg)
  return cfg and cfg.aggroR or 1.00,
    cfg and cfg.aggroG or 0.55,
    cfg and cfg.aggroB or 0.00,
    1
end

local function PurgeColor(cfg)
  local general = GeneralDB()
  return cfg and cfg.purgeR or tonumber(general and (general.hlPurgeColorR or general.purgeBorderColorR)) or 1.00,
    cfg and cfg.purgeG or tonumber(general and (general.hlPurgeColorG or general.purgeBorderColorG)) or 0.85,
    cfg and cfg.purgeB or tonumber(general and (general.hlPurgeColorB or general.purgeBorderColorB)) or 0.00,
    1
end

local function BossTargetColor(cfg)
  if cfg and cfg.bossTargetR then
    return cfg.bossTargetR or 1, cfg.bossTargetG or 0.82, cfg.bossTargetB or 0, 1
  end
  local general = GeneralDB()
  local color = general and general.bossTargetHighlightColor
  if type(color) == "table" then
    return tonumber(color[1]) or 1, tonumber(color[2]) or 0.82, tonumber(color[3]) or 0, tonumber(color[4]) or 1
  end
  return 1, 0.82, 0, 1
end

local function NormalBorderColor(cfg)
  return cfg and cfg.r or 0, cfg and cfg.g or 0, cfg and cfg.b or 0, cfg and cfg.a or 1
end

local function HighlightPriorityOrder(cfg)
  local order = cfg and cfg.prioEnabled == true and cfg.prioOrder
  if type(order) == "table" then
    return order
  end
  return DEFAULT_HIGHLIGHT_PRIORITY
end

local function PriorityIndex(cfg, key)
  local order = HighlightPriorityOrder(cfg)
  for i = 1, #order do
    if order[i] == key then
      return i
    end
  end
  return nil
end

local function HighlightBorderLevel(cfg, key)
  if key == "dispel" then
    return BORDER_LEVEL_OVER_NATIVE_DISPEL
  end
  if cfg and cfg.dispel == true and key then
    local dispelIndex = PriorityIndex(cfg, "dispel")
    local keyIndex = PriorityIndex(cfg, key)
    if dispelIndex and keyIndex and dispelIndex < keyIndex then
      return BORDER_LEVEL_NORMAL
    end
  end
  return BORDER_LEVEL_OVER_NATIVE_DISPEL
end

local function RuntimeHighlightBorderLevel(frame, cfg, key)
  if key == "dispel" then return frame._msufBorderRuntimeLevelDispel or BORDER_LEVEL_OVER_NATIVE_DISPEL end
  if key == "aggro" then return frame._msufBorderRuntimeLevelAggro or HighlightBorderLevel(cfg, key) end
  if key == "purge" then return frame._msufBorderRuntimeLevelPurge or HighlightBorderLevel(cfg, key) end
  if key == "bossTarget" then return frame._msufBorderRuntimeLevelBossTarget or HighlightBorderLevel(cfg, key) end
  return BORDER_LEVEL_OVER_NATIVE_DISPEL
end

local function ApplyResolvedBorder(frame, cfg, source, level, thickness, r, g, b, a)
  r, g, b, a = r or 0, g or 0, b or 0, a or 1
  thickness = thickness or 1
  local layer = cfg and cfg.layer or 0
  local offset = (level or BORDER_LEVEL_DEFAULT) + layer
  local strata = cfg and cfg.strata or nil
  local secret = IsSecretValue(r) or IsSecretValue(g) or IsSecretValue(b) or IsSecretValue(a)
    or IsSecretValue(strata)
  if not secret
    and frame._msufBorderVisualCfg == cfg
    and frame._msufBorderVisualSource == source
    and frame._msufBorderVisualOffset == offset
    and frame._msufBorderVisualStrata == strata
    and frame._msufBorderVisualThickness == thickness
    and frame._msufBorderVisualR == r
    and frame._msufBorderVisualG == g
    and frame._msufBorderVisualB == b
    and frame._msufBorderVisualA == a
  then
    return true
  end
  frame._msufBorderVisualCfg = cfg
  frame._msufBorderVisualSource = source
  frame._msufBorderVisualOffset = offset
  frame._msufBorderVisualStrata = secret and nil or strata
  frame._msufBorderVisualThickness = thickness
  if secret then
    frame._msufBorderVisualR, frame._msufBorderVisualG = nil, nil
    frame._msufBorderVisualB, frame._msufBorderVisualA = nil, nil
  else
    frame._msufBorderVisualR, frame._msufBorderVisualG = r, g
    frame._msufBorderVisualB, frame._msufBorderVisualA = b, a
  end
  SetBorderOverlayLevel(frame, level, strata, layer)
  LayoutBorder(frame, thickness)
  SetBorder(frame, true, r, g, b, a)
  return true
end

local function HideResolvedBorder(frame)
  if frame._msufBorderVisualSource == "hidden" and frame._msufBorderShown == false then return end
  frame._msufBorderVisualCfg = frame._msufBorderRuntimeCfg
  frame._msufBorderVisualSource = "hidden"
  SetBorder(frame, false)
end

local function ApplyHighlightBorder(frame, cfg, key, testActive)
  if key == "dispel" then
    if testActive and DispelTestApplies(frame) then
      local r, g, b, a = DispelTestColor(frame)
      return ApplyResolvedBorder(frame, cfg, key, RuntimeHighlightBorderLevel(frame, cfg, key),
        frame._msufBorderRuntimeHighlightThickness, r, g, b, a)
    end
    if cfg.dispel == true and frame._msufA3DispelActive == true then
      return ApplyResolvedBorder(frame, cfg, key, RuntimeHighlightBorderLevel(frame, cfg, key),
        frame._msufBorderRuntimeHighlightThickness,
        frame._msufA3DispelR or 0.25,
        frame._msufA3DispelG or 0.75,
        frame._msufA3DispelB or 1,
        frame._msufA3DispelA or 1)
    end
  elseif key == "aggro" then
    if (testActive and AggroTestApplies(frame)) or (cfg.aggro and IsAggroBorderUnit(frame) and ThreatState(frame)) then
      return ApplyResolvedBorder(frame, cfg, key, RuntimeHighlightBorderLevel(frame, cfg, key),
        frame._msufBorderRuntimeHighlightThickness, AggroColor(cfg))
    end
  elseif key == "purge" then
    if testActive and PurgeTestApplies(frame) then
      return ApplyResolvedBorder(frame, cfg, key, RuntimeHighlightBorderLevel(frame, cfg, key),
        frame._msufBorderRuntimeHighlightThickness, PurgeColor(cfg))
    end
  elseif key == "bossTarget" then
    if (testActive and BossTargetTestApplies(frame)) or BossTargetState(frame, cfg) then
      return ApplyResolvedBorder(frame, cfg, key, RuntimeHighlightBorderLevel(frame, cfg, key),
        frame._msufBorderRuntimeHighlightThickness, BossTargetColor(cfg))
    end
  end
  return false
end

function Borders.Create(frame)
  LayoutBorder(frame, 1)
end

function Borders.Apply(frame, spec)
  local cfg = spec and spec.border
  if frame then
    local customPriority = cfg and cfg.prioEnabled == true and type(cfg.prioOrder) == "table"
    frame._msufBorderRuntimeCfg = cfg
    frame._msufBorderRuntimeGroup = spec and spec.scope == "group" or nil
    frame._msufBorderRuntimeAggroMode = cfg and NormalizeAggroMode(cfg.aggroMode) or nil
    frame._msufBorderRuntimeHighlightThickness = tonumber(cfg and cfg.highlightThickness) or 3
    frame._msufBorderRuntimeNormalThickness = BorderNormalThickness(cfg)
    frame._msufBorderRuntimePriority = customPriority and cfg.prioOrder or nil
    frame._msufBorderRuntimeCustomPriority = customPriority and true or nil
    frame._msufBorderRuntimeLevelDispel = cfg and HighlightBorderLevel(cfg, "dispel") or nil
    frame._msufBorderRuntimeLevelAggro = cfg and HighlightBorderLevel(cfg, "aggro") or nil
    frame._msufBorderRuntimeLevelPurge = cfg and HighlightBorderLevel(cfg, "purge") or nil
    frame._msufBorderRuntimeLevelBossTarget = cfg and HighlightBorderLevel(cfg, "bossTarget") or nil
    frame._msufBorderRuntimeNormal = BorderNormalEnabled(cfg) or nil
    frame._msufBorderRuntimeHighlight = BorderHighlightEnabled(frame, cfg) or nil
    frame._msufBorderVisualCfg = nil
  end
  if not cfg or not (BorderNormalEnabled(cfg) or BorderHighlightEnabled(frame, cfg)) then
    LayoutBorder(frame, 1)
    SetBorder(frame, false)
  elseif cfg.aggro == true or cfg.dispel == true or (cfg.bossTarget == true and IsBossUnit(frame and frame.MSUFUnitKey)) then
    LayoutBorder(frame, BorderHighlightThickness(cfg))
    Borders.Update(frame, "MSUF_BORDER_APPLY", frame.MSUFUnitKey)
  else
    SetBorderOverlayLevel(frame, BORDER_LEVEL_NORMAL, cfg and cfg.strata, cfg and cfg.layer)
    LayoutBorder(frame, BorderNormalThickness(cfg))
    SetBorder(frame, true, NormalBorderColor(cfg))
  end
end

function Borders.IsEnabled(frame, spec)
  local cfg = spec and spec.border
  return BorderNormalEnabled(cfg) or BorderHighlightEnabled(frame, cfg) or false
end

function Borders.GetActiveVisual(frame)
  if not frame or frame._msufBorderShown ~= true then return nil end
  local cfg = frame._msufBorderRuntimeCfg
  if cfg == nil and frame.MSUFSpec then cfg = frame.MSUFSpec.border end
  local source = "normal"
  if cfg then
    local testActive = _G.MSUF_BorderTestModesActive == true
    local priority = HighlightPriorityOrder(cfg)
    for i = 1, #priority do
      local key = priority[i]
      local active = false
      if key == "dispel" then
        active = (testActive and DispelTestApplies(frame))
          or (cfg.dispel == true and frame._msufA3DispelActive == true)
      elseif key == "aggro" then
        active = (testActive and AggroTestApplies(frame))
          or (cfg.aggro == true and IsAggroBorderUnit(frame) and ThreatState(frame))
      elseif key == "purge" then
        active = testActive and PurgeTestApplies(frame)
      elseif key == "bossTarget" then
        active = (testActive and BossTargetTestApplies(frame)) or BossTargetState(frame, cfg)
      end
      if active then source = key break end
    end
  end
  return {
    source = source,
    r = frame._msufBorderR,
    g = frame._msufBorderG,
    b = frame._msufBorderB,
    a = frame._msufBorderA,
    secret = frame._msufBorderSecretColor == true,
  }
end

if UF then
  function UF.GetActiveBorderVisual(frame)
    return Borders.GetActiveVisual(frame)
  end
end

function Borders.Disable(frame)
  if frame and frame.MSUFUnitDispelOverlay then
    frame.MSUFUnitDispelOverlay:Hide()
  end
  if frame then
    frame._msufBorderRuntimeCfg = nil
    frame._msufBorderRuntimeGroup = nil
    frame._msufBorderRuntimeAggroMode = nil
    frame._msufBorderRuntimeHighlightThickness = nil
    frame._msufBorderRuntimeNormalThickness = nil
    frame._msufBorderRuntimePriority = nil
    frame._msufBorderRuntimeCustomPriority = nil
    frame._msufBorderRuntimeLevelDispel = nil
    frame._msufBorderRuntimeLevelAggro = nil
    frame._msufBorderRuntimeLevelPurge = nil
    frame._msufBorderRuntimeLevelBossTarget = nil
    frame._msufBorderRuntimeNormal = nil
    frame._msufBorderRuntimeHighlight = nil
    frame._msufBorderVisualCfg = nil
    frame._msufBorderVisualSource = nil
  end
  SetBorder(frame, false)
end

function Borders.Update(frame)
  local cfg = frame and frame._msufBorderRuntimeCfg
  if cfg == nil and frame and frame.MSUFSpec then
    cfg = frame.MSUFSpec.border
  end
  local normalEnabled = frame and frame._msufBorderRuntimeNormal == true
  local highlightEnabled = frame and frame._msufBorderRuntimeHighlight == true
  if _G.MSUF_BorderTestModesActive == true then
    highlightEnabled = BorderHighlightEnabled(frame, cfg)
  end
  if not cfg or not (normalEnabled or highlightEnabled) then
    HideResolvedBorder(frame)
    return
  end
  local testActive = _G.MSUF_BorderTestModesActive == true
  if testActive or frame._msufBorderRuntimeCustomPriority == true then
    local priority = frame._msufBorderRuntimePriority or HighlightPriorityOrder(cfg)
    for i = 1, #priority do
      if ApplyHighlightBorder(frame, cfg, priority[i], testActive) then
        return
      end
    end
  else
    -- The default order is fixed. Avoid the four-key generic loop and do not
    -- call disabled highlight resolvers on every threat/dispel event.
    if cfg.dispel == true and ApplyHighlightBorder(frame, cfg, "dispel", false) then return end
    if cfg.aggro == true and ApplyHighlightBorder(frame, cfg, "aggro", false) then return end
    if cfg.bossTarget == true and ApplyHighlightBorder(frame, cfg, "bossTarget", false) then return end
  end
  if not normalEnabled then
    HideResolvedBorder(frame)
    return
  end
  ApplyResolvedBorder(frame, cfg, "normal", BORDER_LEVEL_NORMAL,
    frame._msufBorderRuntimeNormalThickness, NormalBorderColor(cfg))
end

Borders.NoDispatchUpdates = { [Borders.Update] = true }

UF.RegisterElement("Borders", Borders)

local function RefreshUnitDispelFrame(frame)
  if frame then
    Borders.Update(frame, "MSUF_A3_DISPEL_SENSOR", frame.MSUFUnitKey)
    return true
  end
  if UF and UF.RefreshBorders then
    UF.RefreshBorders()
  end
  return true
end

ExportPublic("MSUF_RefreshUnitDispelOverlays", RefreshUnitDispelFrame)
ExportPublic("MSUF_RefreshUnitDispelOverlay", RefreshUnitDispelFrame)
