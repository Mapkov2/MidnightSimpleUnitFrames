--- UnitFrames/Engine/Group/MSUF_UF_Group_Visuals.lua
--- Group-only visual runtime elements.
---
--- This file handles target/focus edge indicators, dispel/debuff visuals,
--- health fade/dead-background behavior, and per-GUID indicator dispatch for
--- group frames. It is an element implementation registered with the UF engine;
--- header creation, roster scanning, and DB compilation live elsewhere.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF

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
local UnitIsConnected = _G.UnitIsConnected
local UnitIsUnit = _G.UnitIsUnit
local tonumber = tonumber
local type = type
local max = math.max
local floor = math.floor
local GetTime = _G.GetTime
local issecretvalue = _G.issecretvalue or function(_) return false end
local IsUnitToken = UF.IsUnitToken or function(unit)
  return issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
end
local ReadConnectedCached = UF.ReadConnectedCached or function(_, unit)
  if not UnitIsConnected then return true, true end
  local connected = UnitIsConnected(unit)
  if issecretvalue(connected) == true or connected == nil then return true, false end
  return connected == true or connected == 1, true
end
local ReadDeadCached = UF.ReadDeadCached or function(_, unit)
  if not (_G.UnitIsDeadOrGhost or _G.UnitIsDead) then return false, true end
  local dead = _G.UnitIsDeadOrGhost and _G.UnitIsDeadOrGhost(unit) or nil
  if (issecretvalue(dead) == true or dead == nil) and _G.UnitIsDead then
    dead = _G.UnitIsDead(unit)
  end
  if issecretvalue(dead) == true or dead == nil then return false, false end
  return dead == true or dead == 1, true
end
local Clamp01 = UF.Clamp01 or function(value, fallback)
  value = tonumber(value)
  if value == nil then value = fallback end
  value = value or 0
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

local EMPTY_EVENTS = {}
local VISUAL_HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local VISUAL_HEALTH_FLAGS_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_FLAGS" }
local VISUAL_FLAGS_EVENTS = { "UNIT_FLAGS" }
local EDGE_KEYS = { "top", "bottom", "left", "right" }
local HEALTH_FADE_SECRET_THROTTLE = 0.1

local function SetAlphaCached(region, alpha, key)
  if not (region and region.SetAlpha) then return end
  alpha = Clamp01(alpha, 1)
  key = key or "_msufGFVisualAlpha"
  if region[key] ~= alpha then
    region:SetAlpha(alpha)
    region[key] = alpha
  end
end

local function SetAlphaFromBoolean(region, value, alphaIfTrue, alphaIfFalse, key)
  if not (region and region.SetAlphaFromBoolean) then
    return false
  end
  region:SetAlphaFromBoolean(value, Clamp01(alphaIfTrue, 1), Clamp01(alphaIfFalse, 1))
  if key then
    region[key] = nil
  end
  return true
end

local function PlainBool(value)
  if issecretvalue(value) == true then
    return nil
  end
  if value == true or value == 1 then
    return true
  end
  if value == false or value == 0 then
    return false
  end
  return nil
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

--- Color writes can receive secret values on Midnight clients. Cache normal
--- values, but pass secret values through and clear cache stamps.
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

--- Prefer Blizzard's alias-aware comparison; its secret combat result can be
--- forwarded directly to SetAlphaFromBoolean.
local function SameUnit(unit, otherUnit)
  if issecretvalue(unit) == true then
    return false
  end
  if type(unit) ~= "string" or unit == "" then
    return false
  end
  local connected, connectedKnown = ReadConnectedCached(nil, otherUnit)
  if connectedKnown == true and connected ~= true then
    return false
  end
  if unit == otherUnit then
    return true
  end
  if UnitIsUnit then
    local same = UnitIsUnit(unit, otherUnit)
    if issecretvalue(same) == true then
      return same
    end
    if same ~= nil then
      return same == true or same == 1
    end
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

local function SetEdgesAlphaFromBoolean(edges, value)
  if not edges then return false end
  local first = edges[EDGE_KEYS[1]]
  if not (first and first.SetAlphaFromBoolean) then return false end
  for i = 1, #EDGE_KEYS do
    local edge = edges[EDGE_KEYS[i]]
    SetShown(edge, true)
    edge:SetAlphaFromBoolean(value, 1, 0)
  end
  return true
end

local function ResetEdgesAlpha(edges)
  if not edges then return end
  for i = 1, #EDGE_KEYS do
    local edge = edges[EDGE_KEYS[i]]
    if edge and edge.SetAlpha then
      edge:SetAlpha(1)
    end
  end
end

local function PrepareUnitEdges(frame, enabled, edgesKey, shownKey, layer, size, r, g, b, indicatorKind)
  local rounded = _G.MSUF_RoundedUF_OnGroupIndicatorPrepared
  if rounded and rounded(frame, indicatorKind, enabled == true, frame and frame[shownKey] == true, size, r, g, b, 1) then
    HideEdges(frame and frame[edgesKey])
    if frame and enabled ~= true then frame[shownKey] = false end
    return
  end
  if not (frame and enabled) then
    HideEdges(frame and frame[edgesKey])
    if frame then
      frame[shownKey] = false
      frame[shownKey .. "Secret"] = nil
    end
    return
  end
  local edges = frame[edgesKey] or {}
  frame[edgesKey] = edges
  for i = 1, #EDGE_KEYS do
    local key = EDGE_KEYS[i]
    local edge = edges[key]
    if not edge then
      edge = frame:CreateTexture(nil, "OVERLAY", nil, layer)
      edges[key] = edge
    end
    LayoutTargetEdge(frame, edge, key, size)
    SetColorTextureCached(edge, r, g, b, 1)
    SetShown(edge, false)
  end
  ResetEdgesAlpha(edges)
  frame[shownKey] = false
  frame[shownKey .. "Secret"] = nil
end

local function UpdateUnitEdges(frame, cfg, enabled, unit, edgesKey, shownKey, showOverride, indicatorKind)
  if not (frame and cfg) then
    if frame then frame[shownKey] = false end
    SetEdgesShown(frame and frame[edgesKey], false)
    return
  end
  local show = showOverride
  local secretShow = issecretvalue(show) == true
  if not secretShow and type(show) ~= "boolean" then
    show = nil
  end
  if secretShow then
    -- Secret comparison results can only be consumed by restricted-safe region
    -- setters; never branch on or coerce the value in Lua.
  elseif show == nil then
    if enabled == true and frame.MSUFUnitKey then
      show = SameUnit(frame.MSUFUnitKey, unit)
    else
      show = false
    end
    secretShow = issecretvalue(show) == true
  else
    show = show == true and enabled
  end
  if enabled ~= true then
    show = false
    secretShow = false
  end
  local secretKey = shownKey .. "Secret"
  local rounded = _G.MSUF_RoundedUF_OnGroupIndicatorChanged
  if rounded and rounded(frame, indicatorKind, show) then
    if secretShow then
      frame[shownKey] = nil
      frame[secretKey] = true
    else
      frame[shownKey] = show
      frame[secretKey] = nil
    end
    HideEdges(frame[edgesKey])
    return
  end
  if secretShow then
    if SetEdgesAlphaFromBoolean(frame[edgesKey], show) then
      frame[shownKey] = nil
      frame[secretKey] = true
    else
      frame[shownKey] = false
      frame[secretKey] = nil
      SetEdgesShown(frame[edgesKey], false)
    end
    return
  end
  if frame[secretKey] == true then
    ResetEdgesAlpha(frame[edgesKey])
    frame[secretKey] = nil
  end
  if frame[shownKey] == show then
    return
  end
  frame[shownKey] = show
  SetEdgesShown(frame[edgesKey], show)
end

local function PrepareTarget(frame, cfg)
  PrepareUnitEdges(frame, cfg and cfg.targetIndicator == true,
    "MSUFGFTargetEdges", "_msufGFTargetVisualShown", 7, 2,
    cfg and cfg.targetR or 1, cfg and cfg.targetG or 1, cfg and cfg.targetB or 1, "target")
end

local function UpdateTarget(frame, cfg, showOverride)
  UpdateUnitEdges(frame, cfg, cfg and cfg.targetIndicator == true,
    "target", "MSUFGFTargetEdges", "_msufGFTargetVisualShown", showOverride, "target")
end

local function PrepareFocus(frame, cfg)
  local size = max(1, floor((tonumber(cfg and cfg.focusSize) or 2) + 0.5))
  local offset = tonumber(cfg and cfg.focusOffset) or 0
  PrepareUnitEdges(frame, cfg and cfg.focusIndicator == true,
    "MSUFGFFocusEdges", "_msufGFFocusVisualShown", 6, size + offset,
    cfg and cfg.focusR or 0.5, cfg and cfg.focusG or 0.5, cfg and cfg.focusB or 1, "focus")
end

local function UpdateFocus(frame, cfg, showOverride)
  UpdateUnitEdges(frame, cfg, cfg and cfg.focusIndicator == true,
    "focus", "MSUFGFFocusEdges", "_msufGFFocusVisualShown", showOverride, "focus")
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
  local rounded = _G.MSUF_RoundedUF_OnGroupAuraVisualCreated
  if rounded then rounded(frame, tex) end
  return tex
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

local function UpdateAuraDebuffStripeOnly(frame, cfg)
  UpdateDebuffStripe(frame, cfg)
end

local indicatorDriver
local targetIndicatorCount = 0
local focusIndicatorCount = 0
local targetDriverRegistered
local focusDriverRegistered
local connectionDriverRegistered
local targetIndicatorCurrentGUID
local focusIndicatorCurrentGUID
local targetIndicatorGUIDKnown
local focusIndicatorGUIDKnown
local targetIndicatorSecretFrame
local focusIndicatorSecretFrame
local targetIndicatorClickHint
local indicatorGUIDBuckets = {}

local function PlainUnitGUID(unit)
  if not IsUnitToken(unit) then
    return nil, true
  end
  local guid = UnitGUID(unit)
  if issecretvalue(guid) == true then
    return nil, false
  end
  if type(guid) ~= "string" or guid == "" then
    return nil, true
  end
  return guid, true
end

local function PlainConnectedUnitGUID(unit)
  local guid, guidKnown = PlainUnitGUID(unit)
  if guidKnown ~= true or guid == nil then
    return guid, guidKnown
  end
  local connected, connectedKnown = ReadConnectedCached(nil, unit)
  if connectedKnown ~= true then
    return nil, false
  end
  if connected ~= true then
    return nil, true
  end
  return guid, true
end

local function IndicatorFrameTracked(frame)
  return frame and (frame._msufGFTargetIndicatorRegistered == true or frame._msufGFFocusIndicatorRegistered == true)
end

local function RemoveIndicatorGUIDFrame(frame, guid)
  if not (frame and guid) then return end
  local bucket = indicatorGUIDBuckets[guid]
  local index = bucket and bucket.index
  local i = index and index[frame]
  if not i then return end
  local list = bucket.frames
  local last = #list
  local tail = list[last]
  list[i] = tail
  list[last] = nil
  index[frame] = nil
  if tail and tail ~= frame then
    index[tail] = i
  end
  if last <= 1 then
    indicatorGUIDBuckets[guid] = nil
  end
end

local function AddIndicatorGUIDFrame(frame, guid)
  if not (frame and guid and IndicatorFrameTracked(frame)) then return end
  local bucket = indicatorGUIDBuckets[guid]
  if not bucket then
    bucket = { frames = {}, index = {} }
    indicatorGUIDBuckets[guid] = bucket
  elseif bucket.index[frame] then
    return
  end
  local list = bucket.frames
  local n = #list + 1
  list[n] = frame
  bucket.index[frame] = n
end

--- Keep the last readable identity while combat restrictions make UnitGUID
--- secret. Clearing it there would destroy the O(1) bucket as well as the
--- correct frame identity.
local function RefreshIndicatorUnitGUID(frame)
  if not frame then
    return nil, true
  end
  local guid, guidKnown = PlainUnitGUID(frame.MSUFUnitKey)
  local oldGuid = frame._msufGFVisualUnitGUID
  if guidKnown ~= true then
    return oldGuid, false
  end
  if oldGuid == guid then
    if guid then AddIndicatorGUIDFrame(frame, guid) end
    return guid, true
  end
  if oldGuid then RemoveIndicatorGUIDFrame(frame, oldGuid) end
  frame._msufGFVisualUnitGUID = guid
  if guid then AddIndicatorGUIDFrame(frame, guid) end
  return guid, true
end

local function RunIndicatorBucket(guid, update, registrationKey, show)
  if not guid then return end
  local bucket = indicatorGUIDBuckets[guid]
  local list = bucket and bucket.frames
  if not list then return end
  local live = GF and GF.frames
  local first
  for i = 1, #list do
    local frame = list[i]
    if frame and frame[registrationKey] == true
      and frame._msufGFVisualUnitGUID == guid
      and (not live or live[frame] == true) then
      first = first or frame
      if update then update(frame, frame._msufGFVisualRuntimeGroup, show) end
    end
  end
  return first
end

local function UpdateIndicatorCandidate(frame, update, watchedUnit, registrationKey)
  if not (frame and frame[registrationKey] == true) then return end
  local live = GF and GF.frames
  if live and live[frame] ~= true then return end
  local show
  if UnitIsUnit and IsUnitToken(frame.MSUFUnitKey) then
    show = UnitIsUnit(frame.MSUFUnitKey, watchedUnit)
    if issecretvalue(show) ~= true then
      show = show == true or show == 1
    end
  else
    show = SameUnit(frame.MSUFUnitKey, watchedUnit)
  end
  local secretShow = issecretvalue(show) == true
  update(frame, frame._msufGFVisualRuntimeGroup, show)
  return secretShow
end

local function RunIndicatorEvent(event)
  local update, watchedUnit, oldGuid, oldKnown, registrationKey, secretFrame
  if event == "PLAYER_TARGET_CHANGED" then
    update, watchedUnit = UpdateTarget, "target"
    oldGuid, oldKnown = targetIndicatorCurrentGUID, targetIndicatorGUIDKnown
    registrationKey = "_msufGFTargetIndicatorRegistered"
    secretFrame = targetIndicatorSecretFrame
  else
    update, watchedUnit = UpdateFocus, "focus"
    oldGuid, oldKnown = focusIndicatorCurrentGUID, focusIndicatorGUIDKnown
    registrationKey = "_msufGFFocusIndicatorRegistered"
    secretFrame = focusIndicatorSecretFrame
  end

  local newGuid, newKnown = PlainConnectedUnitGUID(watchedUnit)
  if event == "PLAYER_TARGET_CHANGED" then
    targetIndicatorCurrentGUID, targetIndicatorGUIDKnown = newGuid, newKnown
  else
    focusIndicatorCurrentGUID, focusIndicatorGUIDKnown = newGuid, newKnown
  end

  if newKnown == true then
    local secretIsNew
    if oldKnown == true and oldGuid ~= newGuid then
      RunIndicatorBucket(oldGuid, update, registrationKey, false)
    end
    if secretFrame then
      local guid, guidKnown = RefreshIndicatorUnitGUID(secretFrame)
      if guidKnown == true then
        secretIsNew = guid ~= nil and guid == newGuid
        update(secretFrame, secretFrame._msufGFVisualRuntimeGroup, secretIsNew)
      else
        UpdateIndicatorCandidate(secretFrame, update, watchedUnit, registrationKey)
      end
    end
    if secretIsNew ~= true and (oldKnown ~= true or oldGuid ~= newGuid) then
      RunIndicatorBucket(newGuid, update, registrationKey, true)
    end
    if event == "PLAYER_TARGET_CHANGED" then
      targetIndicatorSecretFrame = nil
      targetIndicatorClickHint = nil
    else
      focusIndicatorSecretFrame = nil
    end
    return
  end

  if oldKnown == true and oldGuid then
    secretFrame = RunIndicatorBucket(oldGuid, nil, registrationKey) or secretFrame
  end
  if secretFrame then
    UpdateIndicatorCandidate(secretFrame, update, watchedUnit, registrationKey)
  end
  if event == "PLAYER_TARGET_CHANGED" then
    local clickFrame = targetIndicatorClickHint
    targetIndicatorClickHint = nil
    if clickFrame and clickFrame ~= secretFrame then
      UpdateIndicatorCandidate(clickFrame, update, watchedUnit, registrationKey)
    end
    targetIndicatorSecretFrame = clickFrame or secretFrame
  else
    focusIndicatorSecretFrame = secretFrame
  end
end

local function UpdateConnectionIndicatorFrame(frame, connected)
  if not frame then return end
  if connected ~= true then
    if frame._msufGFTargetIndicatorRegistered == true then
      UpdateTarget(frame, frame._msufGFVisualRuntimeGroup, false)
    end
    if frame._msufGFFocusIndicatorRegistered == true then
      UpdateFocus(frame, frame._msufGFVisualRuntimeGroup, false)
    end
    if targetIndicatorSecretFrame == frame then targetIndicatorSecretFrame = nil end
    if focusIndicatorSecretFrame == frame then focusIndicatorSecretFrame = nil end
    if targetIndicatorClickHint == frame then targetIndicatorClickHint = nil end
    return
  end
  if frame._msufGFTargetIndicatorRegistered == true then
    if UpdateIndicatorCandidate(frame, UpdateTarget, "target", "_msufGFTargetIndicatorRegistered") == true then
      if not targetIndicatorSecretFrame then targetIndicatorSecretFrame = frame end
    end
  end
  if frame._msufGFFocusIndicatorRegistered == true then
    if UpdateIndicatorCandidate(frame, UpdateFocus, "focus", "_msufGFFocusIndicatorRegistered") == true then
      if not focusIndicatorSecretFrame then focusIndicatorSecretFrame = frame end
    end
  end
end

local function UpdateConnectionIndicatorForUnit(frame, _, connected)
  UpdateConnectionIndicatorFrame(frame, connected)
  return true
end

local function IndicatorDriverOnEvent(_, event, unit, isConnected)
  if event == "PLAYER_TARGET_CHANGED" then
    RunIndicatorEvent(event)
  elseif event == "PLAYER_FOCUS_CHANGED" then
    RunIndicatorEvent(event)
  else
    local handled
    if issecretvalue(isConnected) ~= true and isConnected ~= nil and IsUnitToken(unit) then
      local connected = isConnected == true or isConnected == 1
      if GF and GF.ForEachFrameForUnit then
        handled = GF.ForEachFrameForUnit(unit, UpdateConnectionIndicatorForUnit, connected)
      elseif GF and GF.FrameForUnit then
        local frame = GF.FrameForUnit(unit)
        if frame then
          UpdateConnectionIndicatorFrame(frame, connected)
          handled = true
        end
      end
    end
    if handled ~= true then
      if targetDriverRegistered == true then RunIndicatorEvent("PLAYER_TARGET_CHANGED") end
      if focusDriverRegistered == true then RunIndicatorEvent("PLAYER_FOCUS_CHANGED") end
    end
  end
end

local function EnsureIndicatorDriver()
  if indicatorDriver or not CreateFrame then
    return indicatorDriver
  end
  indicatorDriver = CreateFrame("Frame")
  indicatorDriver:SetScript("OnEvent", IndicatorDriverOnEvent)
  return indicatorDriver
end

--- No target/focus event walks the group. Readable identities hit only their
--- GUID bucket; restricted combat updates at most the prior and clicked frame.
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
      targetIndicatorCurrentGUID, targetIndicatorGUIDKnown = PlainConnectedUnitGUID("target")
      driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    else
      driver:UnregisterEvent("PLAYER_TARGET_CHANGED")
      targetIndicatorCurrentGUID, targetIndicatorGUIDKnown = nil, nil
      targetIndicatorSecretFrame = nil
      targetIndicatorClickHint = nil
    end
    targetDriverRegistered = wantTarget
  end
  local wantFocus = focusIndicatorCount > 0
  if wantFocus ~= focusDriverRegistered then
    if wantFocus then
      focusIndicatorCurrentGUID, focusIndicatorGUIDKnown = PlainConnectedUnitGUID("focus")
      driver:RegisterEvent("PLAYER_FOCUS_CHANGED")
    else
      driver:UnregisterEvent("PLAYER_FOCUS_CHANGED")
      focusIndicatorCurrentGUID, focusIndicatorGUIDKnown = nil, nil
      focusIndicatorSecretFrame = nil
    end
    focusDriverRegistered = wantFocus
  end
  local wantConnection = wantTarget or wantFocus
  if wantConnection ~= connectionDriverRegistered then
    if wantConnection then
      driver:RegisterEvent("UNIT_CONNECTION")
    else
      driver:UnregisterEvent("UNIT_CONNECTION")
    end
    connectionDriverRegistered = wantConnection
  end
end

local function IndicatorFrameOnMouseDown(frame, button)
  if button == "LeftButton" and frame._msufGFTargetIndicatorRegistered == true then
    targetIndicatorClickHint = frame
  end
end

local function EnsureIndicatorClickHint(frame)
  if frame and frame._msufGFIndicatorClickHooked ~= true and frame.HookScript then
    frame:HookScript("OnMouseDown", IndicatorFrameOnMouseDown)
    frame._msufGFIndicatorClickHooked = true
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
      RefreshIndicatorUnitGUID(frame)
      EnsureIndicatorClickHint(frame)
    elseif targetIndicatorSecretFrame == frame then
      targetIndicatorSecretFrame = nil
    end
    if targetIndicatorClickHint == frame and target ~= true then
      targetIndicatorClickHint = nil
    end
  end
  local hadFocus = frame._msufGFFocusIndicatorRegistered == true
  if hadFocus ~= focus then
    focusIndicatorCount = focusIndicatorCount + (focus and 1 or -1)
    if focusIndicatorCount < 0 then focusIndicatorCount = 0 end
    frame._msufGFFocusIndicatorRegistered = focus or nil
    if focus then
      RefreshIndicatorUnitGUID(frame)
    elseif focusIndicatorSecretFrame == frame then
      focusIndicatorSecretFrame = nil
    end
  end
  if target ~= true and focus ~= true then
    RemoveIndicatorGUIDFrame(frame, frame._msufGFVisualUnitGUID)
    frame._msufGFVisualUnitGUID = nil
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

local function PercentFromPlainValues(hp, maxHP)
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
  local unit = frame and frame.MSUFUnitKey
  local bar = frame and (frame.hpBar or frame.Health)
  if not (IsUnitToken(unit) and bar) then
    return nil, nil
  end
  local hpUnit = bar._msufHealthValueUnit
  local maxUnit = bar._msufHealthMaxUnit
  local hp = hpUnit == unit and bar._msufHealthValue or nil
  local maxHP = maxUnit == unit and bar._msufHealthMax or nil
  return hp, maxHP
end

--- Health fade is a hotpath visual. Use seeded dispatch values when available
--- and throttle secret-value fallbacks to avoid expensive repeated reads.
local function UpdateHealthFade(frame, cfg, seedHP, seedMaxHP, event, percentReady)
  if not frame.hpBar then return end
  if percentReady == true then seedMaxHP = 100 end
  local rangeAlpha = frame._msufGFRangeHealthAlpha or 1
  local rangeBool = frame._msufGFRangeHealthBool
  local rangeBoolSecret = frame._msufGFRangeHealthBoolSecret == true or issecretvalue(rangeBool) == true
  local rangeBoolKnown = rangeBoolSecret or rangeBool ~= nil
  local rangeBoolIn = frame._msufGFRangeHealthBoolIn or 1
  local rangeBoolOut = frame._msufGFRangeHealthBoolOut or 1
  local keyHP, keyMax = seedHP, seedMaxHP
  local seedHPSecret = issecretvalue(seedHP) == true
  local seedMaxSecret = issecretvalue(seedMaxHP) == true
  local keyHPSecret = seedHPSecret
  local keyMaxSecret = seedMaxSecret
  local keyCacheable = not keyHPSecret
    and not keyMaxSecret
    and keyHP ~= nil
    and keyMax ~= nil
  if not keyCacheable then
    keyHP, keyMax = CachedHealthValues(frame)
    keyHPSecret = issecretvalue(keyHP) == true
    keyMaxSecret = issecretvalue(keyMax) == true
    keyCacheable = not keyHPSecret
      and not keyMaxSecret
      and keyHP ~= nil
      and keyMax ~= nil
  end
  if not keyCacheable and event == "UNIT_HEALTH" and GetTime then
    local now = GetTime()
    local nextAt = frame._msufGFHealthFadeSecretNextAt
    if frame._msufGFHealthFadeSecretRangeAlpha == rangeAlpha
      and frame._msufGFHealthFadeSecretRangeBoolKnown == rangeBoolKnown
      and frame._msufGFHealthFadeSecretRangeBoolIn == rangeBoolIn
      and frame._msufGFHealthFadeSecretRangeBoolOut == rangeBoolOut
      and (frame._msufGFVisualHealthAlpha ~= nil or frame._msufGFVisualHealthBoolApplied == true)
      and nextAt
      and now < nextAt then
      return
    end
    frame._msufGFHealthFadeSecretNextAt = now + HEALTH_FADE_SECRET_THROTTLE
    frame._msufGFHealthFadeSecretRangeAlpha = rangeAlpha
    frame._msufGFHealthFadeSecretRangeBoolKnown = rangeBoolKnown
    frame._msufGFHealthFadeSecretRangeBoolIn = rangeBoolIn
    frame._msufGFHealthFadeSecretRangeBoolOut = rangeBoolOut
  end
  if keyCacheable
    and rangeBoolSecret ~= true
    and frame._msufGFHealthFadeSeedHP == keyHP
    and frame._msufGFHealthFadeSeedMax == keyMax
    and frame._msufGFHealthFadeRangeAlpha == rangeAlpha
    and frame._msufGFHealthFadeRangeBoolKnown == rangeBoolKnown
    and frame._msufGFHealthFadeRangeBool == rangeBool
    and frame._msufGFHealthFadeRangeBoolIn == rangeBoolIn
    and frame._msufGFHealthFadeRangeBoolOut == rangeBoolOut then
    return
  end

  local alpha = 1
  local unit = frame.MSUFUnitKey
  if cfg.healthFadeEnabled == true and IsUnitToken(unit) then
    local pct = keyCacheable and PercentFromPlainValues(keyHP, keyMax) or PercentFromValues(keyHP, keyMax)
    if pct == nil and percentReady ~= true and UnitHealthPercent then
      local raw = UnitHealthPercent(unit)
      if issecretvalue(raw) ~= true then
        pct = tonumber(raw)
      end
    end
    if pct == nil
      and percentReady ~= true
      and not seedHPSecret and seedHP == nil
      and not seedMaxSecret and seedMaxHP == nil
      and UnitHealth and UnitHealthMax then
      local hp, maxHP = UnitHealth(unit), UnitHealthMax(unit)
      pct = PercentFromValues(hp, maxHP)
    end
    if pct and pct >= (cfg.runtimeHealthFadeThreshold or cfg.healthFadeThreshold or 95) then
      alpha = alpha * (cfg.runtimeHealthFadeAlpha or cfg.healthFadeAlpha or 0.45)
    end
  end
  if keyCacheable then
    frame._msufGFHealthFadeSeedHP = keyHP
    frame._msufGFHealthFadeSeedMax = keyMax
    frame._msufGFHealthFadeRangeAlpha = rangeAlpha
    if rangeBoolSecret ~= true then
      frame._msufGFHealthFadeRangeBoolKnown = rangeBoolKnown
      frame._msufGFHealthFadeRangeBool = rangeBool
      frame._msufGFHealthFadeRangeBoolIn = rangeBoolIn
      frame._msufGFHealthFadeRangeBoolOut = rangeBoolOut
    else
      frame._msufGFHealthFadeRangeBoolKnown = nil
      frame._msufGFHealthFadeRangeBool = nil
      frame._msufGFHealthFadeRangeBoolIn = nil
      frame._msufGFHealthFadeRangeBoolOut = nil
    end
    frame._msufGFHealthFadeSecretNextAt = nil
    frame._msufGFHealthFadeSecretRangeAlpha = nil
    frame._msufGFHealthFadeSecretRangeBoolKnown = nil
    frame._msufGFHealthFadeSecretRangeBoolIn = nil
    frame._msufGFHealthFadeSecretRangeBoolOut = nil
  else
    frame._msufGFHealthFadeSeedHP = nil
    frame._msufGFHealthFadeSeedMax = nil
    frame._msufGFHealthFadeRangeAlpha = nil
    frame._msufGFHealthFadeRangeBoolKnown = nil
    frame._msufGFHealthFadeRangeBool = nil
    frame._msufGFHealthFadeRangeBoolIn = nil
    frame._msufGFHealthFadeRangeBoolOut = nil
  end
  if rangeBoolKnown then
    if SetAlphaFromBoolean(frame.hpBar, rangeBool, alpha * rangeBoolIn, alpha * rangeBoolOut, "_msufGFVisualHealthAlpha") then
      frame._msufGFVisualHealthAlpha = nil
      frame._msufGFVisualHealthBoolApplied = true
      return
    end
    local safe = PlainBool(rangeBool)
    if safe ~= nil then
      alpha = alpha * (safe and rangeBoolIn or rangeBoolOut)
    end
  else
    alpha = alpha * rangeAlpha
  end
  if frame._msufGFVisualHealthAlpha == alpha then
    return
  end
  SetAlphaCached(frame.hpBar, alpha, "_msufGFVisualHealthAlpha")
  frame._msufGFVisualHealthAlpha = alpha
  frame._msufGFVisualHealthBoolApplied = nil
end

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
  local element = UF.elements and UF.elements.Health
  local active = frame and frame._msufActiveElements
  local unit = frame and frame.MSUFUnitKey
  if element and element.Update and active and active.Health == true and IsUnitToken(unit) then
    local bar = frame.hpBar
    if bar then
      bar._msufStatusR = nil
      if frame._msufUnitState then frame._msufUnitState.ready = nil end
    end
    element.Update(frame, "MSUF_GF_VISUALS", unit)
  end
  local fn = BarHelper("ApplyBackgrounds")
  if fn then fn(frame, true, false) end
end

local function ResolveGone(frame, cfg, unit, seedHP, event)
  if not IsUnitToken(unit) then
    return false
  end
  local healthEvent = event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
  local state = frame and frame._msufUnitState
  local stateReady = state and state.ready == true
    and state.unit == unit
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
  if issecretvalue(seedHP) ~= true and type(seedHP) == "number" then
    -- Health/Prediction calculator values are the authoritative transition
    -- signal. UnitIsDeadOrGhost can lag behind a positive AI health snapshot.
    return seedHP <= 0
  end
  local deadKnown = stateFresh and state.deadKnown == true
  local dead = deadKnown and state.dead == true or false
  if dead then
    return true
  end
  if not deadKnown then
    local dg, known = ReadDeadCached(frame, unit)
    if known == true and dg == true then
      return true
    end
  end
  return false
end

local function UpdateDeadBg(frame, cfg, seedHP, event)
  local bg = frame.bg
  local unit = frame.MSUFUnitKey
  if not (bg and IsUnitToken(unit)) then return end
  local cached = frame._msufGFDeadBgState
  local gone = ResolveGone(frame, cfg, unit, seedHP, event)
  local firstResolve = cached == nil
  if gone then
    if cached == true and frame._msufHealthBgDynamic ~= true
      and frame._msufPowerBgDynamic ~= true then
      return
    end
    frame._msufGFDeadBgState = true
    local r, g, b = cfg.deadBgR or 0.6, cfg.deadBgG or 0.05, cfg.deadBgB or 0.05
    local a = cfg.deadBgA or 0.9
    local texture = frame._msufGFVisualHealthBackgroundTexture
    if texture == false then
      texture = nil
    elseif texture == nil and frame.MSUFSpec and frame.MSUFSpec.health then
      texture = frame.MSUFSpec.health.backgroundTexture
    end
    ApplyDeadBgColor(bg, texture, r, g, b, a)
    if frame.hpBarBG and frame.hpBarBG ~= bg then
      ApplyDeadBgColor(frame.hpBarBG, texture, r, g, b, a)
    end
    return
  end
  if cached == gone then return end
  frame._msufGFDeadBgState = gone
  if not firstResolve then
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
    local healthActive
    cfg.runtimeHealthFadeThreshold = tonumber(cfg.healthFadeThreshold) or 95
    cfg.runtimeHealthFadeAlpha = tonumber(cfg.healthFadeAlpha) or 0.45
    healthActive = HealthFadeActive(cfg)
    cfg.runtimeOnHealth = healthActive and UpdateHealthFade or nil
    cfg.runtimeOnTarget = cfg.targetIndicator == true and UpdateTarget or nil
    cfg.runtimeOnFocus = cfg.focusIndicator == true and UpdateFocus or nil
    cfg.runtimeOnDeadBg = cfg.deadBgEnabled == true and UpdateDeadBg or nil
    cfg.runtimeOnRangeAlpha = (healthActive == true or (cfg.rangeFadeEnabled == true and cfg.rangeFadeLayerMode == "health")) and RuntimeOnRangeAlpha or nil
    -- Dispel overlays are native AuraButton regions owned by Auras3 GroupSlots.
    -- Keeping the retired texture follower here made an overlay-only profile
    -- retain GroupVisuals in every group-frame lifecycle plan despite having no
    -- event or state producer. The legacy stripe remains here until it has the
    -- same native owner.
    cfg.runtimeOnAuraVisuals = cfg.debuffStripeEnabled == true and UpdateAuraDebuffStripeOnly or nil
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
  local flags = cfg.deadBgEnabled == true
  if health and flags then return VISUAL_HEALTH_FLAGS_EVENTS end
  if health then return VISUAL_HEALTH_EVENTS end
  if flags then return VISUAL_FLAGS_EVENTS end
  -- Health owns UNIT_CONNECTION and forwards the resolved connection state to
  -- the dead-background follower. Do not add a second route that would perform
  -- the same work and break the fused health/connection fast path.
  return EMPTY_EVENTS
end

function GroupVisuals.GetUnitlessEvents(frame, spec)
  return EMPTY_EVENTS
end

UpdateBordersFromVisualState = function(frame)
  local active = frame and frame._msufActiveElements
  local borders = active and active.Borders == true and UF.elements and UF.elements.Borders
  if borders and borders.Update then
    borders.Update(frame, "MSUF_GF_VISUALS", frame.MSUFUnitKey)
  end
end

local function UpdateVisuals(frame, event, updateInfo, seedMaxHP, percentReady)
  local cfg = frame._msufGFVisualRuntimeGroup
  if not cfg then
    local spec = frame.MSUFSpec
    cfg = spec and spec.group
  end
  if not cfg then return end
  if event == "MSUF_GF_UNIT_IDENTITY" or event == "MSUF_GF_UNIT_STRUCTURE" then
    local guid, guidKnown = RefreshIndicatorUnitGUID(frame)
    local fn = cfg.runtimeOnTarget
    if fn then
      if guidKnown == true and targetIndicatorGUIDKnown == true then
        fn(frame, cfg, guid ~= nil and guid == targetIndicatorCurrentGUID)
      elseif frame == targetIndicatorSecretFrame then
        fn(frame, cfg)
      else
        fn(frame, cfg, false)
      end
    end
    fn = cfg.runtimeOnFocus
    if fn then
      if guidKnown == true and focusIndicatorGUIDKnown == true then
        fn(frame, cfg, guid ~= nil and guid == focusIndicatorCurrentGUID)
      elseif frame == focusIndicatorSecretFrame then
        fn(frame, cfg)
      else
        fn(frame, cfg, false)
      end
    end
    fn = cfg.runtimeOnHealth
    if fn then fn(frame, cfg, updateInfo, seedMaxHP, event, percentReady) end
    fn = cfg.runtimeOnDeadBg
    if fn then fn(frame, cfg, nil, event) end
    fn = cfg.runtimeOnAuraVisuals
    if fn then fn(frame, cfg, event) end
    return
  elseif event == "MSUF_GF_VISUALS_APPLY" then
    local guid, guidKnown = RefreshIndicatorUnitGUID(frame)
    local fn = cfg.runtimeOnTarget
    if fn then
      fn(frame, cfg, guidKnown == true and targetIndicatorGUIDKnown == true
        and guid ~= nil and guid == targetIndicatorCurrentGUID)
    end
    fn = cfg.runtimeOnFocus
    if fn then
      fn(frame, cfg, guidKnown == true and focusIndicatorGUIDKnown == true
        and guid ~= nil and guid == focusIndicatorCurrentGUID)
    end
  end

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
      fn(frame, cfg, updateInfo, seedMaxHP, event, percentReady)
    end
    return
  elseif event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then
    local fn = cfg.runtimeOnHealth
    if fn then
      fn(frame, cfg, updateInfo, seedMaxHP, event, percentReady)
    end
    fn = cfg.runtimeOnDeadBg
    if fn then
      fn(frame, cfg, updateInfo, event)
    end
    return
  elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
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
  if fn and event ~= "MSUF_GF_VISUALS_APPLY" then fn(frame, cfg, event) end
  fn = cfg.runtimeOnFocus
  if fn and event ~= "MSUF_GF_VISUALS_APPLY" then fn(frame, cfg, event) end
  fn = cfg.runtimeOnHealth
  if fn then fn(frame, cfg, updateInfo, seedMaxHP, event, percentReady) end
  fn = cfg.runtimeOnDeadBg
  if fn then fn(frame, cfg, nil, event) end
  fn = cfg.runtimeOnAuraVisuals
  if fn then fn(frame, cfg, event) end

  if event == "MSUF_GF_VISUALS_APPLY" then
    UpdateBordersFromVisualState(frame)
  end
end

function GroupVisuals.UpdateGoneState(frame, event, unit, seedHP)
  local fn = frame and frame._msufGFVisualRuntimeGone
  if fn then
    fn(frame, frame._msufGFVisualRuntimeGroup, seedHP, event)
  end
end

function GroupVisuals.Apply(frame)
  if frame then
    frame._msufGFDeadBgState = nil
    frame._msufGFHealthFadeSeedHP = nil
    frame._msufGFHealthFadeSeedMax = nil
    frame._msufGFHealthFadeRangeAlpha = nil
    frame._msufGFHealthFadeRangeBoolKnown = nil
    frame._msufGFHealthFadeRangeBool = nil
    frame._msufGFHealthFadeRangeBoolIn = nil
    frame._msufGFHealthFadeRangeBoolOut = nil
    frame._msufGFHealthFadeSecretRangeBoolKnown = nil
    frame._msufGFHealthFadeSecretRangeBoolIn = nil
    frame._msufGFHealthFadeSecretRangeBoolOut = nil
    frame._msufGFVisualHealthBoolApplied = nil
  end
  CompileVisualRuntime(frame and frame.MSUFSpec)
  local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.group
  if frame then
    local goneFn = cfg and cfg.runtimeOnDeadBg or nil
    frame._msufGFVisualRuntimeGroup = cfg
    frame._msufGFVisualRuntimeGone = goneFn
    frame._msufGFVisualHealthBackgroundTexture = frame.MSUFSpec and frame.MSUFSpec.health and frame.MSUFSpec.health.backgroundTexture or false
    frame._msufUpdateGroupVisualsGoneState = goneFn and GroupVisuals.UpdateGoneState or nil
  end
  SetIndicatorRegistration(frame, cfg and cfg.targetIndicator == true, cfg and cfg.focusIndicator == true)
  PrepareVisuals(frame, cfg)
  UpdateVisuals(frame, "MSUF_GF_VISUALS_APPLY")
end
function GroupVisuals.Update(frame, event, unit, updateInfo, seedMaxHP, percentReady)
  UpdateVisuals(frame, event, updateInfo, seedMaxHP, percentReady)
end

function GroupVisuals.Disable(frame)
  if not frame then return end
  SetIndicatorRegistration(frame, false, false)
  HideEdges(frame.MSUFGFTargetEdges)
  HideEdges(frame.MSUFGFFocusEdges)
  SetShown(frame.MSUFGFDispelOverlay, false)
  SetShown(frame.MSUFGFDebuffStripe, false)
  frame._msufGFTargetVisualShown = false
  frame._msufGFFocusVisualShown = false
  frame._msufGFTargetVisualShownSecret = nil
  frame._msufGFFocusVisualShownSecret = nil
  if frame._msufGFDeadBgState == true then
    RestoreHealthBackground(frame)
  end
  frame._msufGFDeadBgState = nil
  frame._msufGFHealthFadeSeedHP = nil
  frame._msufGFHealthFadeSeedMax = nil
  frame._msufGFHealthFadeRangeAlpha = nil
  frame._msufGFHealthFadeRangeBoolKnown = nil
  frame._msufGFHealthFadeRangeBool = nil
  frame._msufGFHealthFadeRangeBoolIn = nil
  frame._msufGFHealthFadeRangeBoolOut = nil
  frame._msufGFHealthFadeSecretRangeBoolKnown = nil
  frame._msufGFHealthFadeSecretRangeBoolIn = nil
  frame._msufGFHealthFadeSecretRangeBoolOut = nil
  frame._msufGFVisualHealthBoolApplied = nil
  frame._msufGFVisualRuntimeGroup = nil
  frame._msufGFVisualRuntimeGone = nil
  frame._msufGFVisualHealthBackgroundTexture = nil
  frame._msufUpdateGroupVisualsGoneState = nil
end

UF.RegisterElement("GroupVisuals", GroupVisuals)
