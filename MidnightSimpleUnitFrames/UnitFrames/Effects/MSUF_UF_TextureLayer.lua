-- Unitframe decorative texture layers (3 slots per frame).
-- Spawns up to three optional SharedMedia textures per unit frame (Blizzard
-- name-bar style decoration). Everything here is cold path: settings changes
-- and frame applies re-stamp the layers; the only events are a lazily
-- registered regen pair (combat/ooc visibility) and target/focus lifecycle
-- events (target-only visibility or class color on dynamic units) -- all
-- registered ONLY while a layer actually uses those features, so an unused
-- feature costs nothing.
-- Each layer is a child frame of the unit frame, so range fade / out-of-combat
-- fade / load conditions are inherited for free; "own alpha" multiplies on top,
-- and the follow toggle maps to SetIgnoreParentAlpha.
local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local CreateFrame = CreateFrame
local CreateColor = _G.CreateColor
local InCombatLockdown = _G.InCombatLockdown
local UnitIsUnit = _G.UnitIsUnit
local type = type
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
local max = math.max
local floor = math.floor
local issecretvalue = _G.issecretvalue or function(_) return false end

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local EDGE_SOFTNESS_MASK_ROOT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\texture_layer_edge_softness_"
local EDGE_SOFTNESS_STEP = 0.02
local EDGE_SOFTNESS_MAX = 0.30
local EDGE_SOFTNESS_MASKS = {}
for level = 1, 15 do
  EDGE_SOFTNESS_MASKS[level] = EDGE_SOFTNESS_MASK_ROOT .. (level < 10 and "0" or "") .. tostring(level) .. ".png"
end

local TextureLayer = {}
MSUF.TextureLayer = TextureLayer
local Layers = MSUF.UF and MSUF.UF.Layers or {}

local SLOT_PREFIXES = { "texLayer", "texLayer2", "texLayer3" }
TextureLayer.SLOT_PREFIXES = SLOT_PREFIXES

local VALID_POINTS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true,
  LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local VALID_STRATA = {
  BACKGROUND = true, LOW = true, MEDIUM = true,
  HIGH = true, DIALOG = true, TOOLTIP = true,
}
local GRADIENT_DIR_SUFFIXES = {
  right = "GradientDirRight",
  left = "GradientDirLeft",
  up = "GradientDirUp",
  down = "GradientDirDown",
}

local function Clamp01(value, fallback)
  value = tonumber(value)
  if value == nil then return fallback end
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

local function ConfForUnitKey(unitKey)
  local db = _G.MSUF_DB
  if not db or type(unitKey) ~= "string" then return nil end
  if unitKey:match("^boss%d+$") then unitKey = "boss" end
  local conf = db[unitKey]
  return type(conf) == "table" and conf or nil
end

local function ResolveLayerTexture(conf, prefix)
  local custom = conf[prefix .. "CustomTexturePath"]
  local sourceMode = conf[prefix .. "SourceMode"]
  if sourceMode ~= "SHAREDMEDIA" and type(custom) == "string" and custom ~= "" then return custom end
  if sourceMode == "PACK" or sourceMode == "CUSTOM" then return WHITE8 end
  local key = conf[prefix .. "Texture"]
  if type(key) == "string" and key ~= "" then
    local resolve = _G.MSUF_ResolveStatusbarTextureKey
    local texture = type(resolve) == "function" and resolve(key) or nil
    if type(texture) == "string" and texture ~= "" then
      return texture
    end
  end
  local barTexture = _G.MSUF_GetBarTexture
  if type(barTexture) == "function" then
    local texture = barTexture()
    if type(texture) == "string" and texture ~= "" then
      return texture
    end
  end
  return WHITE8
end

local function ApplyColorTreatment(tex, conf, prefix)
  local monochrome = conf and conf[prefix .. "ColorTreatment"] == "MONOCHROME"
  if tex and tex.SetDesaturated then
    tex:SetDesaturated(monochrome)
  end
  return monochrome
end
TextureLayer.ApplyColorTreatment = ApplyColorTreatment

local function ResolveAnchorTarget(frame, mode)
  if mode == "HEALTH" then
    return frame.hpBar or frame.Health or frame.healthBar or frame.hpBG or frame
  elseif mode == "POWER" then
    return frame.powerBar or frame.powerBG or frame.power or frame
  elseif mode == "PORTRAIT" then
    return frame.MSUFPortraitHolder or frame.portrait or frame
  end
  return frame
end
TextureLayer.ResolveAnchorTarget = ResolveAnchorTarget

local function RegionDimension(region, method, fallback)
  local fn = region and region[method]
  local value = type(fn) == "function" and fn(region) or nil
  if issecretvalue(value) == true or type(value) ~= "number" or value < 1 then return fallback end
  return value
end

local function ResolveSizeMode(conf, prefix)
  local mode = conf[prefix .. "SizeMode"]
  if mode == "FRAME" or mode == "HEIGHT" or mode == "MANUAL" then return mode end
  return conf[prefix .. "ResponsiveSize"] == true and "FRAME" or "MANUAL"
end
TextureLayer.ResolveSizeMode = ResolveSizeMode

--- Resolves live and preview geometry through one contract. FRAME follows both
--- dimensions, HEIGHT stays square while following frame height (medallions),
--- and MANUAL retains legacy Width/Height semantics. `scale` is 1 live and the
--- mock viewport scale in Menu2 preview.
local function ResolveLayerSize(target, frame, conf, prefix, fallbackW, fallbackH, scale)
  scale = tonumber(scale) or 1
  if scale <= 0 then scale = 1 end
  fallbackW = tonumber(fallbackW) or (100 * scale)
  fallbackH = tonumber(fallbackH) or (16 * scale)
  local frameW = RegionDimension(frame, "GetWidth", fallbackW)
  local frameH = RegionDimension(frame, "GetHeight", fallbackH)
  local targetW = RegionDimension(target, "GetWidth", frameW)
  local targetH = RegionDimension(target, "GetHeight", frameH)
  local mode = ResolveSizeMode(conf, prefix)
  if mode == "FRAME" then
    local width = (targetW + 20 * scale) / 0.82
    local height = (targetH + 10 * scale) / 0.30
    return max(72 * scale, width), max(48 * scale, height)
  elseif mode == "HEIGHT" then
    local size = max(48 * scale, (targetH + 10 * scale) / 0.30)
    return size, size
  end
  local width = tonumber(conf[prefix .. "Width"]) or 0
  if width > 0 then width = width * scale else width = targetW end
  local height = (tonumber(conf[prefix .. "Height"]) or 16) * scale
  return max(1, width), max(1, height)
end
TextureLayer.ResolveLayerSize = ResolveLayerSize

--- FREE uses the selected anchor normally. LEFT/RIGHT add the current target
--- edge to the user's own offset, allowing a square ornament to remain attached
--- while the unit frame changes width. This runs only when layers are stamped.
local function ResolveLayerOffsets(target, frame, conf, prefix, fallbackW, fallbackH, scale)
  scale = tonumber(scale) or 1
  if scale <= 0 then scale = 1 end
  fallbackW = tonumber(fallbackW) or (100 * scale)
  fallbackH = tonumber(fallbackH) or (16 * scale)
  local frameW = RegionDimension(frame, "GetWidth", fallbackW)
  local targetW = RegionDimension(target, "GetWidth", frameW)
  local x = (tonumber(conf[prefix .. "OffsetX"]) or 0) * scale
  local y = (tonumber(conf[prefix .. "OffsetY"]) or 0) * scale
  local edge = conf[prefix .. "EdgeAttach"]
  if edge == "LEFT" then
    x = x - targetW * 0.5
  elseif edge == "RIGHT" then
    x = x + targetW * 0.5
  end
  return x, y
end
TextureLayer.ResolveLayerOffsets = ResolveLayerOffsets

--- Applies the exact anchor, scaled offsets and size contract used by live
--- frames. Menu2 preview calls this same helper after its health, power and
--- portrait regions have their final geometry, avoiding a second layout model.
local function ApplyLayerLayout(holder, frame, conf, prefix, fallbackW, fallbackH, scale)
  local target = ResolveAnchorTarget(frame, conf[prefix .. "AnchorTarget"])
  local point = conf[prefix .. "Anchor"]
  if not VALID_POINTS[point] then point = "TOP" end
  local width, height = ResolveLayerSize(target, frame, conf, prefix, fallbackW, fallbackH, scale)
  local offsetX, offsetY = ResolveLayerOffsets(target, frame, conf, prefix, fallbackW, fallbackH, scale)
  holder:SetSize(width, height)
  holder:ClearAllPoints()
  holder:SetPoint(point, target, point, offsetX, offsetY)
  return target, width, height, point, offsetX, offsetY
end
TextureLayer.ApplyLayerLayout = ApplyLayerLayout

--- Class color for the unit a frame currently shows. 12.x can hand back
--- secret class tokens for hostile units; those fall back to the custom color.
local function ResolveClassRGB(unitKey)
  if type(unitKey) ~= "string" or unitKey == "" then return nil end
  local UnitClass = _G.UnitClass
  if type(UnitClass) ~= "function" then return nil end
  local unit = unitKey == "boss" and "boss1" or unitKey
  local exists = _G.UnitExists
  if type(exists) == "function" and exists(unit) ~= true then return nil end
  local _, token = UnitClass(unit)
  if issecretvalue(token) == true or type(token) ~= "string" or token == "" then return nil end
  -- Keep texture accents on the same effective class palette as health bars,
  -- including MSUF's user-configured class colors. Resolve at apply time so a
  -- settings-cache refresh is reflected without any recurring work.
  local fastClassColor = _G.MSUF_UFCore_GetClassBarColorFast
  if type(fastClassColor) == "function" then
    local r, g, b = fastClassColor(token)
    if issecretvalue(r) ~= true and issecretvalue(g) ~= true and issecretvalue(b) ~= true
      and type(r) == "number" and type(g) == "number" and type(b) == "number" then
      return r, g, b
    end
  end
  local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
  local color = colors and colors[token]
  if not color then return nil end
  return color.r or 1, color.g or 1, color.b or 1
end

--- The regen/retarget driver exists only while some applied layer needs it.
local driver
local driverEvents = {}
local driverUnitFilters = {}
local wantRegenEvents = false
local wantTargetEvents = false
local wantFocusEvents = false
local wantUnitTargetTarget = false
local wantUnitTargetFocus = false
local wantBossEvents = false
local RefreshUnitTextureLayers

local function DriverOnEvent(_, event, unit)
  if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    RefreshUnitTextureLayers(nil)
  elseif event == "PLAYER_TARGET_CHANGED" then
    -- A Current Target layer can belong to Player, Pet, Focus, Boss or ToT,
    -- and both the previously-targeted and newly-targeted frame must repaint.
    RefreshUnitTextureLayers(nil)
  elseif event == "PLAYER_FOCUS_CHANGED" then
    RefreshUnitTextureLayers("focus")
    RefreshUnitTextureLayers("focustarget")
  elseif event == "UNIT_TARGET" then
    if unit == "target" then
      RefreshUnitTextureLayers("targettarget")
    elseif unit == "focus" then
      RefreshUnitTextureLayers("focustarget")
    end
  elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
    RefreshUnitTextureLayers("boss")
  end
end

local function SetDriverUnitEvent(event, wantTarget, wantFocus)
  local wanted = wantTarget or wantFocus
  local filter = wantTarget and (wantFocus and "target,focus" or "target") or (wantFocus and "focus" or nil)
  if (driverEvents[event] == true) == (wanted == true) and driverUnitFilters[event] == filter then return end
  if wanted and not driver then
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", DriverOnEvent)
  end
  if not driver then return end
  driverEvents[event] = wanted or nil
  driverUnitFilters[event] = filter
  driver:UnregisterEvent(event)
  if wantTarget and wantFocus then
    driver:RegisterUnitEvent(event, "target", "focus")
  elseif wantTarget then
    driver:RegisterUnitEvent(event, "target")
  elseif wantFocus then
    driver:RegisterUnitEvent(event, "focus")
  end
end

local function SetDriverEvent(event, wanted)
  if (driverEvents[event] == true) == (wanted == true) then return end
  if wanted and not driver then
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", DriverOnEvent)
  end
  if not driver then return end
  driverEvents[event] = wanted or nil
  if wanted then driver:RegisterEvent(event) else driver:UnregisterEvent(event) end
end

local function SyncDriverEvents()
  SetDriverEvent("PLAYER_REGEN_DISABLED", wantRegenEvents)
  SetDriverEvent("PLAYER_REGEN_ENABLED", wantRegenEvents)
  SetDriverEvent("PLAYER_TARGET_CHANGED", wantTargetEvents)
  SetDriverEvent("PLAYER_FOCUS_CHANGED", wantFocusEvents)
  SetDriverUnitEvent("UNIT_TARGET", wantUnitTargetTarget, wantUnitTargetFocus)
  SetDriverEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", wantBossEvents)
end

local function NoteDynamicNeeds(unitKey, conf, prefix)
  local visibility = conf[prefix .. "Visibility"]
  if visibility == "COMBAT" or visibility == "OOC" then wantRegenEvents = true end
  if visibility == "TARGET" then wantTargetEvents = true end
  if (visibility == "TARGET" or conf[prefix .. "ColorMode"] == "CLASS") then
    if unitKey == "targettarget" then wantUnitTargetTarget = true end
    if unitKey == "focustarget" then wantUnitTargetFocus = true end
  end
  if conf[prefix .. "ColorMode"] == "CLASS" then
    if unitKey == "target" or unitKey == "targettarget" then wantTargetEvents = true end
    if unitKey == "focus" or unitKey == "focustarget" then wantFocusEvents = true end
    if unitKey:match("^boss") then wantBossEvents = true end
  end
end

--- Rounded clipping borrows the dispel-overlay mask hook from RoundedFrames.
--- Masks cannot be detached through that hook, so un-clipping swaps in a fresh
--- texture object (cold path, toggles are rare).
local function WantsRoundedClip(conf, prefix)
  return conf[prefix .. "RoundedClip"] == true and _G.MSUF_RoundedUF_Active == true
    and type(_G.MSUF_RoundedUF_OnDispelOverlayChanged) == "function"
end

local function NewLayerTexture(holder, sublevel)
  local tex = holder:CreateTexture(nil, "ARTWORK", nil, sublevel or 0)
  tex:SetAllPoints(holder)
  return tex
end

--- Edge softness is stored as a normalized fraction (0..0.30). Fifteen tiny
--- standalone masks contain the exact 2%, 4%, ... 30% feather profiles. Mask
--- textures deliberately cannot share an atlas: WoW ignores SetTexCoord on a
--- MaskTexture and would otherwise sample the complete atlas.
local function ResolveEdgeSoftness(value)
  value = tonumber(value) or 0
  if value <= 0 then return 0, 0 end
  if value > EDGE_SOFTNESS_MAX then value = EDGE_SOFTNESS_MAX end
  local level = floor((value / EDGE_SOFTNESS_STEP) + 0.5)
  if level < 1 then return 0, 0 end
  if level > 15 then level = 15 end
  return level * EDGE_SOFTNESS_STEP, level
end
TextureLayer.ResolveEdgeSoftness = ResolveEdgeSoftness
TextureLayer.EDGE_SOFTNESS_MAX = EDGE_SOFTNESS_MAX

local function EnsureSoftEdgeMask(holder, level)
  if level <= 0 or type(holder.CreateMaskTexture) ~= "function" then return nil end
  local mask = holder.softEdgeMask
  if not mask then
    mask = holder:CreateMaskTexture(nil, "ARTWORK")
    if not mask then return nil end
    mask:SetAllPoints(holder)
    holder.softEdgeMask = mask
  end
  if holder.softEdgeMaskLevel ~= level then
    mask:SetTexture(EDGE_SOFTNESS_MASKS[level], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    holder.softEdgeMaskLevel = level
  end
  if mask.Show then mask:Show() end
  return mask
end

local function ClearSoftEdgeMask(holder)
  local tracked = holder.softEdgeMaskedTextures
  if tracked then
    for tex, mask in pairs(tracked) do
      if tex and mask and type(tex.RemoveMaskTexture) == "function" then
        tex:RemoveMaskTexture(mask)
      end
      tracked[tex] = nil
    end
  end
  if holder.softEdgeMask and holder.softEdgeMask.Hide then holder.softEdgeMask:Hide() end
end

local function ApplySoftEdgeMask(holder, textures, rawSoftness)
  local _, level = ResolveEdgeSoftness(rawSoftness)
  if level <= 0 then
    ClearSoftEdgeMask(holder)
    return false
  end
  local mask = EnsureSoftEdgeMask(holder, level)
  if not mask then
    ClearSoftEdgeMask(holder)
    return false
  end
  local active = {}
  for i = 1, #textures do
    local tex = textures[i]
    if tex then active[tex] = true end
  end
  local tracked = holder.softEdgeMaskedTextures
  if not tracked then
    tracked = {}
    holder.softEdgeMaskedTextures = tracked
  end
  for tex, oldMask in pairs(tracked) do
    if not active[tex] or oldMask ~= mask then
      if tex and oldMask and type(tex.RemoveMaskTexture) == "function" then
        tex:RemoveMaskTexture(oldMask)
      end
      tracked[tex] = nil
    end
  end
  for tex in pairs(active) do
    if tracked[tex] ~= mask and type(tex.AddMaskTexture) == "function" then
      tex:AddMaskTexture(mask)
      tracked[tex] = mask
    end
  end
  return true
end
TextureLayer.ApplySoftEdgeMask = ApplySoftEdgeMask

local function EnsureBaseTexture(holder, clipWanted)
  local tex = holder.tex
  if tex and tex._msufTextureLayerRoundedClip == true and not clipWanted then
    tex:Hide()
    tex = nil
  end
  if not tex then
    tex = NewLayerTexture(holder, 0)
    holder.tex = tex
  end
  return tex
end

local function EnsureOverlayTexture(holder, direction, clipWanted)
  local grads = holder.grads
  if not grads then
    grads = {}
    holder.grads = grads
  end
  local tex = grads[direction]
  if tex and tex._msufTextureLayerRoundedClip == true and not clipWanted then
    tex:Hide()
    tex = nil
  end
  if not tex then
    tex = NewLayerTexture(holder, 1)
    tex:SetTexture(WHITE8)
    if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
    grads[direction] = tex
  end
  return tex
end

local function ApplyClip(frame, holder, tex, clipWanted)
  if clipWanted then
    _G.MSUF_RoundedUF_OnDispelOverlayChanged(frame, tex)
    tex._msufTextureLayerRoundedClip = true
  end
end

local function LayerVisible(conf, prefix, frame, unitKey)
  if _G.MSUF_UnitEditModeActive == true then return true end
  local visibility = conf[prefix .. "Visibility"]
  if visibility == "TARGET" then
    local unit = frame and frame.MSUFUnitKey or unitKey
    -- Menu previews have no live unit token; keep the configured art visible
    -- there so the user can edit it. Live frames always pass their token.
    if type(unit) ~= "string" or unit == "" then return true end
    if type(UnitIsUnit) ~= "function" then return false end
    local isTarget = UnitIsUnit("target", unit)
    if issecretvalue(isTarget) == true then return false end
    return isTarget == true or isTarget == 1
  end
  if visibility ~= "COMBAT" and visibility ~= "OOC" then return true end
  local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown() == true
  if visibility == "COMBAT" then return inCombat end
  return not inCombat
end
TextureLayer.LayerVisible = LayerVisible
TextureLayer.ResolveLayerTexture = ResolveLayerTexture
TextureLayer.ResolveClassRGB = ResolveClassRGB

local function ResolveTexCoords(conf, prefix)
  local left, right, top, bottom = 0, 1, 0, 1
  local cropMode = conf[prefix .. "CropMode"]
  if cropMode == "TOP_HALF" then
    bottom = 0.5
  elseif cropMode == "BOTTOM_HALF" then
    top = 0.5
  end
  if conf[prefix .. "MirrorH"] == true then left, right = right, left end
  if conf[prefix .. "MirrorV"] == true then top, bottom = bottom, top end
  return left, right, top, bottom
end
TextureLayer.ResolveTexCoords = ResolveTexCoords

local function ApplyLayerStrata(frame, holder, strata)
  if not (holder and holder.SetFrameStrata) then return end
  -- Legacy per-texture strata must not bypass the addon-wide 0..30 order.
  strata = frame.GetFrameStrata and frame:GetFrameStrata() or nil
  if issecretvalue(strata) == true or strata == nil or strata == "" then return end
  if holder._msufTexLayerStrata ~= strata then
    holder:SetFrameStrata(strata)
    holder._msufTexLayerStrata = strata
  end
end
TextureLayer.ApplyLayerStrata = ApplyLayerStrata

local function ResolveLayerFrameLevel(frame, rawLevel)
  local offset = tonumber(rawLevel) or 1
  if offset < 0 then offset = 0 elseif offset > 30 then offset = 30 end
  if Layers.ElementLevel then return Layers.ElementLevel(offset, 1, 0) end
  local base = frame and frame.GetFrameLevel and (frame:GetFrameLevel() or 0) or 0
  return base + offset
end
TextureLayer.ResolveLayerFrameLevel = ResolveLayerFrameLevel

--- Strata, layer band, parent-alpha behavior and slot alpha are identical in
--- live frames and Menu2. Keeping them here also prevents preview-only layer
--- arithmetic from drifting away from the shared 0..30 element scale.
local function ApplyLayerFrameState(frame, holder, conf, prefix)
  ApplyLayerStrata(frame, holder, conf[prefix .. "Strata"])
  if holder.SetFrameLevel then
    local level = ResolveLayerFrameLevel(frame, conf[prefix .. "Level"])
    if holder._msufTexLayerLevel ~= level then
      holder:SetFrameLevel(level)
      holder._msufTexLayerLevel = level
    end
  end
  if holder.SetIgnoreParentAlpha then
    holder:SetIgnoreParentAlpha(conf[prefix .. "FollowFrameAlpha"] == false)
  end
  holder:SetAlpha(Clamp01(conf[prefix .. "Alpha"], 1))
end
TextureLayer.ApplyLayerFrameState = ApplyLayerFrameState

--- Texture resolution, mirroring, tint, gradients and optional rounded masks
--- are one visual contract for live and preview. Preview may pass a class-color
--- override from its live snapshot; runtime resolves the displayed unit.
local function ApplyLayerVisual(frame, holder, conf, prefix, unitKey, classR, classG, classB)
  local clipWanted = WantsRoundedClip(conf, prefix)
  local tex = EnsureBaseTexture(holder, clipWanted)
  tex:SetTexture(ResolveLayerTexture(conf, prefix))
  ApplyColorTreatment(tex, conf, prefix)
  if tex.SetBlendMode then
    tex:SetBlendMode(conf[prefix .. "BlendMode"] == "ADD" and "ADD" or "BLEND")
  end
  if tex.SetTexCoord then
    tex:SetTexCoord(ResolveTexCoords(conf, prefix))
  end

  local r = Clamp01(conf[prefix .. "ColorR"], 1)
  local g = Clamp01(conf[prefix .. "ColorG"], 1)
  local b = Clamp01(conf[prefix .. "ColorB"], 1)
  if conf[prefix .. "ColorMode"] == "CLASS" then
    local cr, cg, cb = classR, classG, classB
    if cr == nil then cr, cg, cb = ResolveClassRGB(unitKey) end
    if cr ~= nil then r, g, b = Clamp01(cr, r), Clamp01(cg, g), Clamp01(cb, b) end
  end
  if tex.SetGradient and CreateColor then
    local solid = CreateColor(r, g, b, 1)
    tex:SetGradient("HORIZONTAL", solid, solid)
  elseif tex.SetVertexColor then
    tex:SetVertexColor(r, g, b, 1)
  end
  ApplyClip(frame, holder, tex, clipWanted)
  local featherTextures = { tex }

  local gradientOn = conf[prefix .. "GradientEnabled"] == true
  local r2 = Clamp01(conf[prefix .. "Gradient2R"], 0)
  local g2 = Clamp01(conf[prefix .. "Gradient2G"], 0)
  local b2 = Clamp01(conf[prefix .. "Gradient2B"], 0)
  for direction, suffix in pairs(GRADIENT_DIR_SUFFIXES) do
    local value = conf[prefix .. suffix]
    local active = gradientOn and (direction == "right" and value ~= false or value == true)
    if active then
      local overlay = EnsureOverlayTexture(holder, direction, clipWanted)
      local orientation = (direction == "up" or direction == "down") and "VERTICAL" or "HORIZONTAL"
      local minA, maxA = 0, 1
      if direction == "left" or direction == "down" then minA, maxA = 1, 0 end
      if overlay.SetGradient and CreateColor then
        overlay:SetGradient(orientation, CreateColor(r2, g2, b2, minA), CreateColor(r2, g2, b2, maxA))
      elseif overlay.SetVertexColor then
        overlay:SetVertexColor(r2, g2, b2, 0.5)
      end
      ApplyClip(frame, holder, overlay, clipWanted)
      featherTextures[#featherTextures + 1] = overlay
      overlay:Show()
    else
      local overlay = holder.grads and holder.grads[direction]
      if overlay then overlay:Hide() end
    end
  end
  ApplySoftEdgeMask(holder, featherTextures, conf[prefix .. "EdgeSoftness"])
  return tex
end
TextureLayer.ApplyLayerVisual = ApplyLayerVisual

local function ApplySlot(frame, conf, unitKey, slot)
  local prefix = SLOT_PREFIXES[slot]
  local holders = frame._msufTexLayers
  local holder = holders and holders[slot]
  if conf[prefix .. "Enabled"] ~= true or not LayerVisible(conf, prefix, frame, unitKey) then
    if holder then
      ClearSoftEdgeMask(holder)
      holder:Hide()
    end
    return
  end

  if not holder then
    if not holders then
      holders = {}
      frame._msufTexLayers = holders
    end
    holder = CreateFrame("Frame", nil, frame)
    holder:EnableMouse(false)
    holders[slot] = holder
  end

  ApplyLayerFrameState(frame, holder, conf, prefix)

  -- Placement: anchor to the frame or one of its elements.
  ApplyLayerLayout(holder, frame, conf, prefix, 100, 16, 1)

  ApplyLayerVisual(frame, holder, conf, prefix, unitKey)
  holder:Show()
end

local function ApplyToUnitFrame(frame)
  if not frame or frame._msufIsGroupFrame == true then return end
  local unitKey = frame.MSUFUnitKey
  if not unitKey then return end
  local conf = ConfForUnitKey(unitKey)
  if not conf then return end
  for slot = 1, #SLOT_PREFIXES do
    ApplySlot(frame, conf, unitKey, slot)
  end
end
TextureLayer.ApplyToUnitFrame = ApplyToUnitFrame

local function FrameMatchesUnitScope(frame, unit)
  if unit == nil then return true end
  local unitKey = frame and frame.MSUFUnitKey
  if not unitKey then return false end
  if unitKey == unit then return true end
  if unit == "boss" and unitKey:match("^boss%d+$") then return true end
  local UF = MSUF and MSUF.UF
  local units = UF and type(UF.UnitsForConfigKey) == "function" and UF.UnitsForConfigKey(unit) or nil
  for i = 1, #(units or {}) do
    if units[i] == unitKey then return true end
  end
  return false
end

local function RecomputeDriverNeeds(frames)
  wantRegenEvents, wantTargetEvents, wantFocusEvents, wantUnitTargetTarget, wantUnitTargetFocus, wantBossEvents = false, false, false, false, false, false
  for _, frame in pairs(frames) do
    if frame and frame._msufIsGroupFrame ~= true then
      local unitKey = frame.MSUFUnitKey
      local conf = unitKey and ConfForUnitKey(unitKey)
      if conf then
        for slot = 1, #SLOT_PREFIXES do
          local prefix = SLOT_PREFIXES[slot]
          if conf[prefix .. "Enabled"] == true then
            NoteDynamicNeeds(unitKey, conf, prefix)
          end
        end
      end
    end
  end
  SyncDriverEvents()
end

RefreshUnitTextureLayers = function(unit)
  if unit ~= nil then
    unit = tostring(unit)
    if unit == "" or unit == "*" then unit = nil end
    if unit == "tot" or unit == "targetoftarget" then unit = "targettarget" end
  end
  local UF = MSUF and MSUF.UF
  local frames = UF and UF.frames
  if type(frames) ~= "table" then return false end
  for _, frame in pairs(frames) do
    if frame and FrameMatchesUnitScope(frame, unit) then
      ApplyToUnitFrame(frame)
    end
  end
  RecomputeDriverNeeds(frames)
  return true
end
TextureLayer.Refresh = RefreshUnitTextureLayers

do
  local UF = MSUF and MSUF.UF
  if UF and type(UF.RegisterVisualRefreshCallback) == "function" then
    UF.RegisterVisualRefreshCallback("TextureLayer", RefreshUnitTextureLayers)
  end
end

ExportPublic("MSUF_RefreshUnitTextureLayers", RefreshUnitTextureLayers)
