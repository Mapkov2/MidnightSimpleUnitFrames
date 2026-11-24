local _, MSUF = ...
local EventBusRegister = MSUF.Require("MSUF_EventBus_Register", "MSUF_UF_PortraitModel.lua")
local EventBusUnregister = MSUF.Require("MSUF_EventBus_Unregister", "MSUF_UF_PortraitModel.lua")

-- 3D portrait render ("3D"): one PlayerModel per portrait holder, created the
-- first time a 3D spec reaches it and kept for the session.
--
-- The model is another way to draw the portrait image. Holder, background,
-- mask, ring, border, shadow, dragon, cast icon, click target and alpha all
-- stay with MSUF_UF_Elements_Portrait.lua; this module only binds, sizes and
-- frames the model and owns the instanced-combat rule.
--
-- The only 2D fallback is instanced combat (dungeon, raid, PvP) on Midnight
-- and WoW Forever, and only for the units whose identity Blizzard restricts
-- there: target, target of target, pet target, focus, focus target, boss and
-- arena frames, plus party frames unless their option keeps 3D. Player and pet
-- always keep 3D. Bind answers false and the element resolves the native 2D
-- portrait exactly as it would for a 2D spec. Everywhere else the model stays,
-- including open-world combat and out-of-range or offline units.
--
-- Cost contract: SetUnit runs only when the bound unit token or identity
-- changes or the element forces a model refresh (model/portrait events,
-- already coalesced to one per frame by the element). No OnUpdate, timers or polling.
-- The camera is replayed from compiled numbers on OnModelLoaded and when the
-- layout changes them. Classic clients never register the combat rule.

local Model = {}
MSUF.PortraitModel = Model

local CreateFrame = CreateFrame
local UnitGUID = UnitGUID
local IsInInstance = IsInInstance
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local floor = math.floor
local pairs = pairs
local tonumber = tonumber

-- Midnight and WoW Forever make NPC identities secret in instanced combat.
-- Classic has no such restriction, so 3D stays on everywhere there.
local INSTANCE_COMBAT_RULE = MSUF.Client.IsRetail == true

-- Pan travel at +-100 %: a quarter of the model box on each axis.
local PAN_TRAVEL = 0.25

local function IsSecret(value)
  return issecretvalue ~= nil and issecretvalue(value) == true
end

local function SetShown(region, show)
  show = show == true
  if region._msufShown == show then return end
  region._msufShown = show
  region:SetShown(show)
end

-- ---------------------------------------------------------------- camera

-- The portrait camera only sticks on a shown model: zoom and distance set on a
-- hidden one (or before a cached model finished loading) leave the client's
-- full-body camera in place, a tiny figure at the bottom of the portrait. So
-- the camera is set before SetUnit, again after it, on OnModelLoaded and on
-- every OnShow.
local function ApplyCamera(model)
  if model.SetPortraitZoom then model:SetPortraitZoom(1) end
  if model.SetCamDistanceScale then model:SetCamDistanceScale(model._msufCamScale or 1) end
  if model.SetPosition then model:SetPosition(0, 0, 0) end
  if model.SetViewTranslation then
    model:SetViewTranslation(model._msufTransX or 0, model._msufTransY or 0)
  end
  local facing = model._msufFacing or 0
  if model.SetFacing then
    model:SetFacing(facing)
  elseif model.SetRotation then
    model:SetRotation(facing)
  end
end

function Model.Ensure(holder)
  local model = holder and holder.model3D
  if model then return model end
  if not (holder and CreateFrame) then return nil end
  model = CreateFrame("PlayerModel", nil, holder)
  if not (model and model.SetUnit) then return nil end
  model:EnableMouse(false)
  -- Hiding for a cast icon or the combat fallback must not drop the loaded
  -- model: showing it again for the same GUID then costs no SetUnit.
  if model.SetKeepModelOnHide then model:SetKeepModelOnHide(true) end
  -- Loading is asynchronous and may reset the camera after SetUnit returns.
  model:SetScript("OnModelLoaded", ApplyCamera)
  model:SetScript("OnShow", ApplyCamera)
  model:Hide()
  model._msufShown = false
  holder.model3D = model
  return model
end

--- Layout-time only. `width`/`height` are the holder's effective extents. The
--- model shares the holder's frame level: above the holder's own background,
--- ring and image regions, below the border frame, inset shadow, dragon,
--- portrait auras and click target, which all sit at least one level higher.
function Model.Layout(holder, p, width, height)
  local model = holder and holder.model3D
  if not (model and p) then return end
  local level = holder._msufLevel or holder:GetFrameLevel()
  if model._msufLevel ~= level then
    model:SetFrameLevel(level)
    model._msufLevel = level
  end
  width = tonumber(width) or 0
  height = tonumber(height) or 0
  local inset = p.modelInset or 1
  local insetX = width > 0 and floor((width * (1 - inset) * 0.5) + 0.5) or 0
  local insetY = height > 0 and floor((height * (1 - inset) * 0.5) + 0.5) or 0
  if model._msufInsetX ~= insetX or model._msufInsetY ~= insetY then
    model:ClearAllPoints()
    model:SetPoint("TOPLEFT", holder, "TOPLEFT", insetX, -insetY)
    model:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -insetX, insetY)
    model._msufInsetX, model._msufInsetY = insetX, insetY
  end
  -- Same direction as the 2D pan: a positive zoom centre shows more of the
  -- right/upper side, so the model itself moves left/down.
  local camScale = p.modelCamScale or 1
  local transX = -(p.modelPanX or 0) * (width - (2 * insetX)) * PAN_TRAVEL
  local transY = -(p.modelPanY or 0) * (height - (2 * insetY)) * PAN_TRAVEL
  local facing = p.modelFacing or 0
  if model._msufCamScale ~= camScale or model._msufTransX ~= transX
    or model._msufTransY ~= transY or model._msufFacing ~= facing then
    model._msufCamScale, model._msufTransX, model._msufTransY, model._msufFacing = camScale, transX, transY, facing
    ApplyCamera(model)
  end
end

-- ---------------------------------------------------------------- ring hole

--- Inverted shape masks for the solid ring of a shaped 3D portrait. That ring
--- is a filled shape under the image: opaque 2D art hides its middle, a
--- transparent model would not. tools/build-portrait-model-holes.py builds the
--- art with a white margin of RING_HOLE_PAD of the shape size on every side, so
--- CLAMP wrapping keeps the outer band of any ring thickness.
local MASKS = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
local RING_HOLES = {
  CIRCLE = MASKS .. "portrait_model_hole_circle.tga",
  ROUNDED = MASKS .. "portrait_model_hole_rounded.tga",
  DIAMOND = MASKS .. "portrait_model_hole_diamond.tga",
}
local RING_HOLE_PAD = 0.5

function Model.RingHoleTexture(shape)
  return RING_HOLES[shape]
end

--- Layout-time only; the element calls it when the ring geometry key changes.
--- A nil texture detaches the hole again (2D render or a non-shaped ring).
function Model.LayoutRingHole(holder, ring, holeTexture, width, height)
  local hole = holder.ringHoleMask
  if not holeTexture then
    if hole and ring._msufHoleAttached then
      ring:RemoveMaskTexture(hole)
      ring._msufHoleAttached = nil
    end
    return
  end
  if not hole then
    if not (holder.CreateMaskTexture and ring.AddMaskTexture) then return end
    hole = holder:CreateMaskTexture()
    holder.ringHoleMask = hole
  end
  local padX, padY = width * RING_HOLE_PAD, height * RING_HOLE_PAD
  hole:ClearAllPoints()
  hole:SetPoint("TOPLEFT", holder, "TOPLEFT", -padX, padY)
  hole:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", padX, -padY)
  if hole._msufTexture ~= holeTexture then
    hole:SetTexture(holeTexture, "CLAMP", "CLAMP")
    hole._msufTexture = holeTexture
  end
  if not ring._msufHoleAttached then
    ring:AddMaskTexture(hole)
    ring._msufHoleAttached = true
  end
end

-- ---------------------------------------------------------------- instanced combat

local tracked = {}
local trackedCount = 0
local ruleRegistered = false
local inInstance, inCombat, ruleClosed = false, false, false
local refreshFrame
local RULE_KEY = "MSUF_UF_PORTRAIT_MODEL_COMBAT"
local RULE_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

local function ReadInstance()
  if not IsInInstance then return false end
  local inside = IsInInstance()
  return inside == true or inside == 1
end

local function ReadCombat()
  return InCombatLockdown ~= nil and InCombatLockdown() == true
end

--- The element hands over its refresh entry once it has loaded.
function Model.SetRefreshHandler(handler)
  refreshFrame = handler
end

-- Compiled specs decide who keeps 3D: player and pet unit frames always,
-- party frames when their option is on. Previews never fall back.
local function RuleApplies(frame, p)
  return p.modelInstanceCombat ~= true and frame._msufGFIsPreviewFrame ~= true
end

local function RuleBlocks(frame, p)
  return ruleClosed and RuleApplies(frame, p)
end

local function OnRuleEvent(event)
  if event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
  else
    inInstance, inCombat = ReadInstance(), ReadCombat()
  end
  local closed = inInstance and inCombat
  if closed == ruleClosed then return end
  ruleClosed = closed
  if not refreshFrame then return end
  for frame in pairs(tracked) do
    local p = frame._msufPortraitRuntimeCfg
    if p and p.render == "3D" and RuleApplies(frame, p) then
      refreshFrame(frame)
    end
  end
end

--- A frame with a 3D spec. Registers the combat rule on first use only.
function Model.Track(frame)
  if not INSTANCE_COMBAT_RULE or not frame or tracked[frame] then return end
  tracked[frame] = true
  trackedCount = trackedCount + 1
  if ruleRegistered then return end
  for i = 1, #RULE_EVENTS do
    EventBusRegister(RULE_EVENTS[i], RULE_KEY, OnRuleEvent)
  end
  ruleRegistered = true
  inInstance, inCombat = ReadInstance(), ReadCombat()
  ruleClosed = inInstance and inCombat
end

function Model.Untrack(frame)
  if not (frame and tracked[frame]) then return end
  tracked[frame] = nil
  trackedCount = trackedCount - 1
  if trackedCount > 0 or not ruleRegistered then return end
  trackedCount = 0
  for i = 1, #RULE_EVENTS do
    EventBusUnregister(RULE_EVENTS[i], RULE_KEY)
  end
  ruleRegistered = false
  ruleClosed = false
end

-- ---------------------------------------------------------------- binding

--- SetUnit's result is ignored on purpose: instanced combat is the only reason
--- for the 2D portrait, so a refused or slow load keeps the model frame.
local function BindUnit(model, unit, guid, generation, visible)
  if visible ~= false then SetShown(model, true) end
  ApplyCamera(model)
  model:SetUnit(unit)
  model._msufUnit, model._msufGUID, model._msufGeneration = unit, guid, generation
  ApplyCamera(model)
end

--- Live frames. `guid` may be passed when the caller already read a plain one.
--- `generation` is the element's identity counter for target, focus and their
--- targets; while a GUID is secret it is the only proof of an unchanged unit.
--- Returns false only under the instanced-combat rule (or without a model).
--- `visible` false binds without showing (an active cast icon covers it).
function Model.Bind(frame, holder, unit, p, guid, force, visible, generation)
  if not unit or RuleBlocks(frame, p) then return false end
  local model = holder.model3D or Model.Ensure(holder)
  if not model then return false end
  if guid == nil then
    guid = UnitGUID and UnitGUID(unit)
    if IsSecret(guid) then guid = nil end
  end
  local same = model._msufUnit == unit
  if same then
    if guid ~= nil then
      same = model._msufGUID == guid
    else
      same = generation == nil or model._msufGeneration == generation
    end
  end
  if force == true or not same then
    BindUnit(model, unit, guid, generation, visible)
  elseif guid ~= nil then
    model._msufGeneration = generation
  end
  SetShown(model, visible ~= false)
  return true
end

--- Preview scenes: no combat rule (the menu and Edit Mode never run in it).
--- A sample without a readable unit shows the player as its stand-in.
function Model.BindScene(holder, unit, p)
  local model = holder and (holder.model3D or Model.Ensure(holder))
  if not (model and p) then return false end
  local guid = unit and UnitGUID and UnitGUID(unit)
  if unit == nil or IsSecret(guid) or guid == nil then
    unit = "player"
    guid = UnitGUID and UnitGUID("player")
    if IsSecret(guid) then guid = nil end
  end
  if model._msufUnit ~= unit or model._msufGUID ~= guid then
    BindUnit(model, unit, guid, nil, true)
  end
  SetShown(model, true)
  return true
end

--- Shows or hides a bound model without touching its unit.
function Model.SetVisible(holder, visible)
  local model = holder and holder.model3D
  if model then SetShown(model, visible) end
end

--- 2D/class render, disabled portrait or fallback. The loaded model is kept.
function Model.Hide(holder)
  local model = holder and holder.model3D
  if model then SetShown(model, false) end
end

-- Test and diagnostics seam: the rule state without exposing the tables.
function Model.RuleState()
  return ruleRegistered, ruleClosed, trackedCount
end
