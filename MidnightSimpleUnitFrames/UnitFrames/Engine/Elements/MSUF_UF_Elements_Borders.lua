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
local floor = V.floor or math.floor
local IsNil = V.IsNil or function(value) return value == nil end
local NotSecretValue = V.NotSecretValue or function(_) return true end
local IsSecretValue = _G.issecretvalue or function(_) return false end
local EMPTY_EVENTS = V.EMPTY_EVENTS or {}
local BORDER_THREAT_EVENTS = V.BORDER_THREAT_EVENTS or { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }
local BOSS_TARGET_EVENTS = { "PLAYER_TARGET_CHANGED" }
local SetShown = V.SetShown

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
  if cfg and cfg.bossTarget == true and IsBossUnit(frame and frame.unit) then
    return BOSS_TARGET_EVENTS
  end
  return EMPTY_EVENTS
end

local EDGE_KEYS = { "top", "bottom", "left", "right" }
local DEFAULT_HIGHLIGHT_PRIORITY = { "dispel", "aggro", "purge", "bossTarget" }
local BORDER_LEVEL_NORMAL = 35
local BORDER_LEVEL_DEFAULT = 40
local BORDER_LEVEL_OVER_NATIVE_DISPEL = 50

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
  if strata == nil or strata == "" or strata == "AUTO" then
    strata = frame.GetFrameStrata and frame:GetFrameStrata() or nil
  end
  if strata and overlay._msufBorderStrata ~= strata and (not overlay.GetFrameStrata or overlay:GetFrameStrata() ~= strata) then
    overlay:SetFrameStrata(strata)
    overlay._msufBorderStrata = strata
  end
end

local function SetBorderOverlayLevel(frame, offset, strata)
  if not frame then return end
  offset = offset or BORDER_LEVEL_DEFAULT
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
  local unit = frame and frame.unit
  if unit == "player" or unit == "target" or unit == "focus" then return true end
  return IsBossUnit(unit)
    or (frame and (frame._msufBorderRuntimeGroup == true
      or frame._msufIsGroupFrame == true
      or frame._msufCoreScope == "group"))
end

local function IsPurgeBorderUnit(frame)
  local unit = frame and frame.unit
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
    return IsBossUnit(frame.unit)
  end
  return frame.unit == scope or frame.configKey == scope or frame.unitKey == scope
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
    and IsBossUnit(frame and frame.unit)
end

local function BossTargetState(frame, cfg)
  if not (cfg and cfg.bossTarget == true and UnitIsUnit and frame and IsBossUnit(frame.unit)) then
    return false
  end
  local isTarget = UnitIsUnit(frame.unit, "target")
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
  if cfg and cfg.bossTarget == true and IsBossUnit(frame and frame.unit) then
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
  if not (UnitThreatSituation and frame and frame.unit) then
    return false
  end
  local unit = frame.unit
  if frame._msufBorderRuntimeGroup == true
    or frame._msufIsGroupFrame == true
    or frame._msufCoreScope == "group" then
    local exists = UnitExists and UnitExists(unit)
    if not IsNil(exists) and NotSecretValue(exists) and exists == false then
      return false
    end
    local mode = frame._msufBorderRuntimeAggroMode
    if mode == nil then
      local spec = frame.MSUFSpec
      local cfg = spec and spec.border
      mode = cfg and cfg.aggroMode
    end
    mode = tostring(mode or "ALL"):upper()
    if mode == "TANK_ONLY" then mode = "TANK"
    elseif mode == "HEALER_ONLY" then mode = "HEALER" end
    if mode == "TANK" or mode == "HEALER" or mode == "NON_TANK" then
      local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
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
    local status = UnitThreatSituation(unit)
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

local function ApplyHighlightBorder(frame, cfg, key, testActive)
  if key == "dispel" then
    if testActive and DispelTestApplies(frame) then
      local r, g, b, a = DispelTestColor(frame)
      SetBorderOverlayLevel(frame, HighlightBorderLevel(cfg, key), cfg and cfg.strata)
      LayoutBorder(frame, BorderHighlightThickness(cfg))
      SetBorder(frame, true, r, g, b, a)
      return true
    end
    if cfg.dispel == true and frame._msufA3DispelActive == true then
      SetBorderOverlayLevel(frame, HighlightBorderLevel(cfg, key), cfg and cfg.strata)
      LayoutBorder(frame, BorderHighlightThickness(cfg))
      SetBorder(frame, true,
        frame._msufA3DispelR or 0.25,
        frame._msufA3DispelG or 0.75,
        frame._msufA3DispelB or 1,
        frame._msufA3DispelA or 1)
      return true
    end
  elseif key == "aggro" then
    if (testActive and AggroTestApplies(frame)) or (cfg.aggro and IsAggroBorderUnit(frame) and ThreatState(frame)) then
      SetBorderOverlayLevel(frame, HighlightBorderLevel(cfg, key), cfg and cfg.strata)
      LayoutBorder(frame, BorderHighlightThickness(cfg))
      SetBorder(frame, true, AggroColor(cfg))
      return true
    end
  elseif key == "purge" then
    if testActive and PurgeTestApplies(frame) then
      SetBorderOverlayLevel(frame, HighlightBorderLevel(cfg, key), cfg and cfg.strata)
      LayoutBorder(frame, BorderHighlightThickness(cfg))
      SetBorder(frame, true, PurgeColor(cfg))
      return true
    end
  elseif key == "bossTarget" then
    if (testActive and BossTargetTestApplies(frame)) or BossTargetState(frame, cfg) then
      SetBorderOverlayLevel(frame, HighlightBorderLevel(cfg, key), cfg and cfg.strata)
      LayoutBorder(frame, BorderHighlightThickness(cfg))
      SetBorder(frame, true, BossTargetColor(cfg))
      return true
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
    frame._msufBorderRuntimeCfg = cfg
    frame._msufBorderRuntimeGroup = spec and spec.scope == "group" or nil
    frame._msufBorderRuntimeAggroMode = cfg and cfg.aggroMode or nil
    frame._msufBorderRuntimeHighlightThickness = tonumber(cfg and cfg.highlightThickness) or 3
    frame._msufBorderRuntimeNormal = BorderNormalEnabled(cfg) or nil
    frame._msufBorderRuntimeHighlight = BorderHighlightEnabled(frame, cfg) or nil
  end
  if not cfg or not (BorderNormalEnabled(cfg) or BorderHighlightEnabled(frame, cfg)) then
    LayoutBorder(frame, 1)
    SetBorder(frame, false)
  elseif cfg.aggro == true or cfg.dispel == true or (cfg.bossTarget == true and IsBossUnit(frame and frame.unit)) then
    LayoutBorder(frame, BorderHighlightThickness(cfg))
    Borders.Update(frame, "MSUF_BORDER_APPLY", frame.unit)
  else
    SetBorderOverlayLevel(frame, BORDER_LEVEL_NORMAL, cfg and cfg.strata)
    LayoutBorder(frame, BorderNormalThickness(cfg))
    SetBorder(frame, true, NormalBorderColor(cfg))
  end
end

function Borders.IsEnabled(frame, spec)
  local cfg = spec and spec.border
  return BorderNormalEnabled(cfg) or BorderHighlightEnabled(frame, cfg) or false
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
    frame._msufBorderRuntimeNormal = nil
    frame._msufBorderRuntimeHighlight = nil
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
    SetBorder(frame, false)
    return
  end
  local testActive = _G.MSUF_BorderTestModesActive == true
  local priority = HighlightPriorityOrder(cfg)
  for i = 1, #priority do
    if ApplyHighlightBorder(frame, cfg, priority[i], testActive) then
      return
    end
  end
  if not normalEnabled then
    SetBorder(frame, false)
    return
  end
  SetBorderOverlayLevel(frame, BORDER_LEVEL_NORMAL, cfg and cfg.strata)
  LayoutBorder(frame, BorderNormalThickness(cfg))
  SetBorder(frame, true, NormalBorderColor(cfg))
end

UF.RegisterElement("Borders", Borders)

local function RefreshUnitDispelFrame(frame)
  if frame then
    Borders.Update(frame, "MSUF_A3_DISPEL_SENSOR", frame.unit)
    return true
  end
  if UF and UF.RefreshBorders then
    UF.RefreshBorders()
  end
  return true
end

ExportPublic("MSUF_RefreshUnitDispelOverlays", RefreshUnitDispelFrame)
ExportPublic("MSUF_RefreshUnitDispelOverlay", RefreshUnitDispelFrame)
