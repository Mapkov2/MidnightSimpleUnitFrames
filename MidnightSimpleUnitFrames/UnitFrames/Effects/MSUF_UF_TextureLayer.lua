-- Unitframe decorative texture layers (3 slots per frame).
-- Spawns up to three optional SharedMedia textures per unit frame (Blizzard
-- name-bar style decoration). Settings changes and frame applies re-stamp the
-- layers. Conditional visibility/class colors use lazily registered lifecycle
-- events; HP gradient colors reuse the owning Health element's existing update
-- and only while a layer requests them. An unused feature costs no event work.
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
local UnitHealthPercent = _G.UnitHealthPercent
local CurveAPI = _G.C_CurveUtil
local LuaCurveType = _G.Enum and _G.Enum.LuaCurveType
local GradientColor = MSUF.UFBarTextCommon and MSUF.UFBarTextCommon.GradientColor
local HealthGradientColorFromValues = MSUF.UFBarTextCommon and MSUF.UFBarTextCommon.HealthGradientColorFromValues
local PreviewHealthGradientColor = MSUF.UFBarTextCommon and MSUF.UFBarTextCommon.PreviewHealthGradientColor
local type = type
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
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
local function BuildSlotKeys(prefix)
  return {
    prefix = prefix,
    Enabled = prefix .. "Enabled",
    CustomTexturePath = prefix .. "CustomTexturePath",
    Texture = prefix .. "Texture",
    ColorTreatment = prefix .. "ColorTreatment",
    Visibility = prefix .. "Visibility",
    TargetOnly = prefix .. "TargetOnly",
    HealthCondition = prefix .. "HealthCondition",
    HealthThreshold = prefix .. "HealthThreshold",
    HealthLowAlphaEnabled = prefix .. "HealthLowAlphaEnabled",
    HealthLowAlpha = prefix .. "HealthLowAlpha",
    ColorMode = prefix .. "ColorMode",
    HealthAboveMode = prefix .. "HealthAboveMode",
    RoundedClip = prefix .. "RoundedClip",
    Strata = prefix .. "Strata",
    Level = prefix .. "Level",
    FollowFrameAlpha = prefix .. "FollowFrameAlpha",
    Alpha = prefix .. "Alpha",
    AnchorTarget = prefix .. "AnchorTarget",
    Anchor = prefix .. "Anchor",
    Width = prefix .. "Width",
    Height = prefix .. "Height",
    OffsetX = prefix .. "OffsetX",
    OffsetY = prefix .. "OffsetY",
    BlendMode = prefix .. "BlendMode",
    CropMode = prefix .. "CropMode",
    MirrorH = prefix .. "MirrorH",
    MirrorV = prefix .. "MirrorV",
    ColorR = prefix .. "ColorR",
    ColorG = prefix .. "ColorG",
    ColorB = prefix .. "ColorB",
    GradientEnabled = prefix .. "GradientEnabled",
    Gradient2R = prefix .. "Gradient2R",
    Gradient2G = prefix .. "Gradient2G",
    Gradient2B = prefix .. "Gradient2B",
    GradientDirRight = prefix .. "GradientDirRight",
    GradientDirLeft = prefix .. "GradientDirLeft",
    GradientDirUp = prefix .. "GradientDirUp",
    GradientDirDown = prefix .. "GradientDirDown",
    EdgeSoftness = prefix .. "EdgeSoftness",
  }
end
local SLOT_KEYS = {
  BuildSlotKeys(SLOT_PREFIXES[1]),
  BuildSlotKeys(SLOT_PREFIXES[2]),
  BuildSlotKeys(SLOT_PREFIXES[3]),
}
local SLOT_BITS = { 1, 2, 4 }

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

local function ResolveLayerTexture(conf, prefix, keys)
  local custom = conf[keys and keys.CustomTexturePath or (prefix .. "CustomTexturePath")]
  if type(custom) == "string" and custom ~= "" then return custom end
  local key = conf[keys and keys.Texture or (prefix .. "Texture")]
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

local function ApplyColorTreatment(tex, conf, prefix, keys)
  local monochrome = conf
    and conf[keys and keys.ColorTreatment or (prefix .. "ColorTreatment")] == "MONOCHROME"
  if conf and conf[keys and keys.ColorMode or (prefix .. "ColorMode")] == "HEALTH"
    and conf[keys and keys.HealthAboveMode or (prefix .. "HealthAboveMode")] == "CUSTOM" then
    monochrome = true
  end
  if tex and tex.SetDesaturated then
    -- Always stamp both states because texture regions are reused across
    -- profile changes and Menu2 edits.
    tex:SetDesaturated(monochrome)
  end
  return monochrome
end
TextureLayer.ApplyColorTreatment = ApplyColorTreatment

local function ResolveAnchorTarget(frame, mode)
  if mode == "HEALTH" then
    return frame.hpBar or frame.Health or frame
  elseif mode == "POWER" then
    return frame.powerBar or frame.power or frame
  elseif mode == "PORTRAIT" then
    return frame.MSUFPortraitHolder or frame.portrait or frame
  end
  return frame
end

--- Class color for the unit a frame currently shows. 12.x can hand back
--- secret class tokens for hostile units; those fall back to the custom color.
local function ResolveClassRGB(unitKey)
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
local RefreshDynamicTextureLayers
local ApplyHealthStateFrame
local DYNAMIC_MASK_FIELDS = {
  "_msufTexLayerRegenMask",
  "_msufTexLayerTargetMask",
  "_msufTexLayerTargetColorMask",
  "_msufTexLayerFocusMask",
  "_msufTexLayerFocusColorMask",
  "_msufTexLayerUnitTargetTargetMask",
  "_msufTexLayerUnitTargetTargetColorMask",
  "_msufTexLayerUnitTargetFocusMask",
  "_msufTexLayerUnitTargetFocusColorMask",
  "_msufTexLayerBossMask",
  "_msufTexLayerBossColorMask",
}
local dynamicFrameLists, dynamicFrameCounts = {}, {}
for i = 1, #DYNAMIC_MASK_FIELDS do
  local field = DYNAMIC_MASK_FIELDS[i]
  dynamicFrameLists[field] = {}
  dynamicFrameCounts[field] = 0
end

local function DriverOnEvent(_, event, unit)
  if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    RefreshDynamicTextureLayers("_msufTexLayerRegenMask")
  elseif event == "PLAYER_TARGET_CHANGED" then
    RefreshDynamicTextureLayers("_msufTexLayerTargetMask", "_msufTexLayerTargetColorMask")
  elseif event == "PLAYER_FOCUS_CHANGED" then
    RefreshDynamicTextureLayers("_msufTexLayerFocusMask", "_msufTexLayerFocusColorMask")
  elseif event == "UNIT_TARGET" then
    if unit == "target" then
      RefreshDynamicTextureLayers("_msufTexLayerUnitTargetTargetMask",
        "_msufTexLayerUnitTargetTargetColorMask")
    elseif unit == "focus" then
      RefreshDynamicTextureLayers("_msufTexLayerUnitTargetFocusMask",
        "_msufTexLayerUnitTargetFocusColorMask")
    end
  elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
    RefreshDynamicTextureLayers("_msufTexLayerBossMask", "_msufTexLayerBossColorMask")
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

local function AddMaskBit(mask, bit)
  return mask % (bit + bit) >= bit and mask or (mask + bit)
end

-- Compile the exact slot set each dynamic event can affect. The masks are
-- rebuilt only by the cold visual-refresh path; combat/target events merely
-- consume them and never rescan configuration or restamp unrelated slots.
local function CompileDynamicMasks(frame, unitKey, conf)
  local regenMask, targetMask, focusMask = 0, 0, 0
  local unitTargetTargetMask, unitTargetFocusMask, bossMask = 0, 0, 0
  local targetColorMask, focusColorMask = 0, 0
  local unitTargetTargetColorMask, unitTargetFocusColorMask, bossColorMask = 0, 0, 0
  local healthMask, healthColorMask, healthDirectGradientMask = 0, 0, 0
  local bossUnit = unitKey:match("^boss") ~= nil
  for slot = 1, #SLOT_KEYS do
    local keys = SLOT_KEYS[slot]
    if conf[keys.Enabled] == true then
      local bit = SLOT_BITS[slot]
      local visibility = conf[keys.Visibility]
      local targetOnly = conf[keys.TargetOnly] == true or visibility == "TARGET"
      local colorMode = conf[keys.ColorMode]
      local classColor = colorMode == "CLASS"
        or (colorMode == "HEALTH" and conf[keys.HealthAboveMode] == "CLASS")
      if colorMode == "HEALTH" or conf[keys.HealthCondition] == "BELOW"
        or conf[keys.HealthLowAlphaEnabled] == true then
        healthMask = AddMaskBit(healthMask, bit)
      end
      if colorMode == "HEALTH" then
        healthColorMask = AddMaskBit(healthColorMask, bit)
        local aboveMode = conf[keys.HealthAboveMode]
        if aboveMode ~= "CLASS" and aboveMode ~= "CUSTOM" then
          healthDirectGradientMask = AddMaskBit(healthDirectGradientMask, bit)
        end
      end
      if visibility == "COMBAT" or visibility == "OOC" then
        regenMask = AddMaskBit(regenMask, bit)
      end
      -- A Current Target layer can belong to any displayed single unit; both
      -- the previous and new match must repaint on PLAYER_TARGET_CHANGED.
      if targetOnly then
        targetMask = AddMaskBit(targetMask, bit)
      end
      if unitKey == "target" or unitKey == "targettarget" then
        if classColor then
          if targetOnly then
            targetMask = AddMaskBit(targetMask, bit)
          else
            targetColorMask = AddMaskBit(targetColorMask, bit)
          end
        end
      end
      if unitKey == "focus" or unitKey == "focustarget" then
        if targetOnly then
          focusMask = AddMaskBit(focusMask, bit)
        elseif classColor then
          focusColorMask = AddMaskBit(focusColorMask, bit)
        end
      end
      if unitKey == "targettarget" and (targetOnly or classColor) then
        if targetOnly then
          unitTargetTargetMask = AddMaskBit(unitTargetTargetMask, bit)
        else
          unitTargetTargetColorMask = AddMaskBit(unitTargetTargetColorMask, bit)
        end
      end
      if unitKey == "focustarget" and (targetOnly or classColor) then
        if targetOnly then
          unitTargetFocusMask = AddMaskBit(unitTargetFocusMask, bit)
        else
          unitTargetFocusColorMask = AddMaskBit(unitTargetFocusColorMask, bit)
        end
      end
      if bossUnit and (targetOnly or classColor) then
        if targetOnly then
          bossMask = AddMaskBit(bossMask, bit)
        else
          bossColorMask = AddMaskBit(bossColorMask, bit)
        end
      end
    end
  end
  frame._msufTexLayerRegenMask = regenMask > 0 and regenMask or nil
  frame._msufTexLayerTargetMask = targetMask > 0 and targetMask or nil
  frame._msufTexLayerTargetColorMask = targetColorMask > 0 and targetColorMask or nil
  frame._msufTexLayerFocusMask = focusMask > 0 and focusMask or nil
  frame._msufTexLayerFocusColorMask = focusColorMask > 0 and focusColorMask or nil
  frame._msufTexLayerUnitTargetTargetMask = unitTargetTargetMask > 0 and unitTargetTargetMask or nil
  frame._msufTexLayerUnitTargetTargetColorMask = unitTargetTargetColorMask > 0
    and unitTargetTargetColorMask or nil
  frame._msufTexLayerUnitTargetFocusMask = unitTargetFocusMask > 0 and unitTargetFocusMask or nil
  frame._msufTexLayerUnitTargetFocusColorMask = unitTargetFocusColorMask > 0
    and unitTargetFocusColorMask or nil
  frame._msufTexLayerBossMask = bossMask > 0 and bossMask or nil
  frame._msufTexLayerBossColorMask = bossColorMask > 0 and bossColorMask or nil
  frame._msufTexLayerHealthMask = healthMask > 0 and healthMask or nil
  frame._msufTexLayerHealthColorMask = healthColorMask > 0 and healthColorMask or nil
  frame._msufTexLayerHealthDirectGradientMask = healthDirectGradientMask > 0 and healthDirectGradientMask or nil
  frame._msufTexLayerHealthUpdate = healthMask > 0 and ApplyHealthStateFrame or nil
  if regenMask > 0 then wantRegenEvents = true end
  if targetMask > 0 or targetColorMask > 0 then wantTargetEvents = true end
  if focusMask > 0 or focusColorMask > 0 then wantFocusEvents = true end
  if unitTargetTargetMask > 0 or unitTargetTargetColorMask > 0 then wantUnitTargetTarget = true end
  if unitTargetFocusMask > 0 or unitTargetFocusColorMask > 0 then wantUnitTargetFocus = true end
  -- Match the previous registration contract: boss lifecycle events exist only
  -- for class-colored boss layers; TARGET visibility is refreshed incidentally
  -- when such a layer is present, just as the former scoped full refresh did.
  if bossUnit then
    for slot = 1, #SLOT_KEYS do
      local keys = SLOT_KEYS[slot]
      local colorMode = conf[keys.ColorMode]
      if conf[keys.Enabled] == true and (colorMode == "CLASS"
          or (colorMode == "HEALTH" and conf[keys.HealthAboveMode] == "CLASS")) then
        wantBossEvents = true
        break
      end
    end
  end
end

--- Rounded clipping borrows the dispel-overlay mask hook from RoundedFrames.
--- Masks cannot be detached through that hook, so un-clipping swaps in a fresh
--- texture object (cold path, toggles are rare).
local function WantsRoundedClip(conf, prefix, keys)
  return conf[keys and keys.RoundedClip or (prefix .. "RoundedClip")] == true
    and _G.MSUF_RoundedUF_Active == true
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
  local active = holder.softEdgeActiveTextures
  if not active then
    active = {}
    holder.softEdgeActiveTextures = active
  else
    for tex in pairs(active) do active[tex] = nil end
  end
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
    holder.clipApplied = nil
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

local function LayerVisible(conf, prefix, frame, unitKey, keys)
  if _G.MSUF_UnitEditModeActive == true then return true end
  local visibility = conf[keys and keys.Visibility or (prefix .. "Visibility")]
  local targetOnly = conf[keys and keys.TargetOnly or (prefix .. "TargetOnly")] == true
    or visibility == "TARGET"
  local unit = frame and frame.MSUFUnitKey or unitKey
  -- Menu previews have no live unit token. Treat every non-health condition as
  -- matched there so the configured art remains editable.
  if type(unit) ~= "string" or unit == "" then return true end
  if targetOnly then
    if type(UnitIsUnit) ~= "function" then return false end
    local isTarget = UnitIsUnit("target", unit)
    if issecretvalue(isTarget) == true then return false end
    if isTarget ~= true and isTarget ~= 1 then return false end
  end
  if visibility == "TARGET" then visibility = "ALWAYS" end
  if visibility ~= "COMBAT" and visibility ~= "OOC" then return true end
  local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown() == true
  if visibility == "COMBAT" then return inCombat end
  return not inCombat
end
TextureLayer.LayerVisible = LayerVisible
TextureLayer.ResolveLayerTexture = ResolveLayerTexture
TextureLayer.ResolveClassRGB = ResolveClassRGB

local function ResolveTexCoords(conf, prefix, keys)
  local left, right, top, bottom = 0, 1, 0, 1
  local cropMode = conf[keys and keys.CropMode or (prefix .. "CropMode")]
  if cropMode == "TOP_HALF" then
    bottom = 0.5
  elseif cropMode == "BOTTOM_HALF" then
    top = 0.5
  end
  if conf[keys and keys.MirrorH or (prefix .. "MirrorH")] == true then left, right = right, left end
  if conf[keys and keys.MirrorV or (prefix .. "MirrorV")] == true then top, bottom = bottom, top end
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

local function ApplyBaseColor(holder, tex, r, g, b)
  if tex.SetGradient and CreateColor then
    -- One SetGradient call with equal ends keeps the base texture solid and
    -- doubles as the "clear gradient" path after profile/copy changes. Reuse
    -- the ColorMixin so recurring dynamic-unit events allocate nothing.
    local solid = holder._msufTexLayerSolidColor
    if not solid then
      solid = CreateColor(r, g, b, 1)
      holder._msufTexLayerSolidColor = solid
    elseif solid.SetRGBA then
      solid:SetRGBA(r, g, b, 1)
    else
      solid.r, solid.g, solid.b, solid.a = r, g, b, 1
    end
    tex:SetGradient("HORIZONTAL", solid, solid)
  elseif tex.SetVertexColor then
    tex:SetVertexColor(r, g, b, 1)
  end
  holder._msufTexLayerBaseR = r
  holder._msufTexLayerBaseG = g
  holder._msufTexLayerBaseB = b
end

-- Dynamic HP colors may be secret in combat. SetVertexColor explicitly accepts
-- those values in 12.x, while SetGradient does not in tainted execution. Plain
-- values retain the same no-op cache used by the class-color warm path.
local function ApplyHealthBaseColor(holder, tex, r, g, b)
  local secret = issecretvalue(r) == true or issecretvalue(g) == true or issecretvalue(b) == true
  if not secret
    and holder._msufTexLayerBaseR == r
    and holder._msufTexLayerBaseG == g
    and holder._msufTexLayerBaseB == b then return end
  if tex.SetVertexColor then
    tex:SetVertexColor(r, g, b, 1)
  else
    ApplyBaseColor(holder, tex, r, g, b)
    return
  end
  if secret then
    holder._msufTexLayerBaseR = nil
    holder._msufTexLayerBaseG = nil
    holder._msufTexLayerBaseB = nil
  else
    holder._msufTexLayerBaseR = r
    holder._msufTexLayerBaseG = g
    holder._msufTexLayerBaseB = b
  end
end

local function HealthThreshold(conf, keys)
  local threshold = Clamp01(conf[keys.HealthThreshold], 0.35)
  if threshold < 0.01 then threshold = 0.01 end
  return threshold
end

local function PlainHealthPercent(hp, maxHP)
  if issecretvalue(hp) == true or issecretvalue(maxHP) == true then return nil end
  hp, maxHP = tonumber(hp), tonumber(maxHP)
  if not hp or not maxHP or maxHP <= 0 then return nil end
  local pct = hp / maxHP
  if pct < 0 then return 0 end
  if pct > 1 then return 1 end
  return pct
end

local function SetHolderAlpha(holder, alpha)
  if not holder or alpha == nil then return end
  local secret = issecretvalue(alpha) == true
  local cachedAlpha = holder._msufTexLayerOwnAlpha
  -- A secret curve result is valid input for Region:SetAlpha, but it must
  -- never be cached: reading/comparing that value later from tainted Lua is
  -- forbidden. Also tolerate holders contaminated by the previous ternary
  -- assignment so the fix takes effect without requiring a fresh frame.
  if not secret and issecretvalue(cachedAlpha) ~= true and cachedAlpha == alpha then return end
  holder:SetAlpha(alpha)
  if secret then
    holder._msufTexLayerOwnAlpha = nil
  else
    holder._msufTexLayerOwnAlpha = alpha
  end
end

local function EnsureHealthAlphaCurve(holder, threshold, belowAlpha, aboveAlpha)
  if not (holder and CurveAPI and CurveAPI.CreateCurve) then return nil end
  if holder._msufTexLayerHealthAlphaCurve
    and holder._msufTexLayerHealthAlphaThreshold == threshold
    and holder._msufTexLayerHealthAlphaBelow == belowAlpha
    and holder._msufTexLayerHealthAlphaAbove == aboveAlpha then
    return holder._msufTexLayerHealthAlphaCurve
  end
  local curve = CurveAPI.CreateCurve()
  if not curve then return nil end
  if curve.SetType then curve:SetType(LuaCurveType and LuaCurveType.Step or 1) end
  curve:AddPoint(0, belowAlpha)
  curve:AddPoint(threshold, aboveAlpha)
  holder._msufTexLayerHealthAlphaCurve = curve
  holder._msufTexLayerHealthAlphaThreshold = threshold
  holder._msufTexLayerHealthAlphaBelow = belowAlpha
  holder._msufTexLayerHealthAlphaAbove = aboveAlpha
  return curve
end

local function EvaluateUnitCurve(unit, curve)
  if not (UnitHealthPercent and type(unit) == "string" and unit ~= "" and curve) then return nil end
  if unit == "boss" then unit = "boss1" end
  return UnitHealthPercent(unit, true, curve)
end

local function ApplyHealthVisibility(holder, conf, keys, unit, hp, maxHP)
  local baseAlpha = Clamp01(conf[keys.Alpha], 1)
  local lowAlphaEnabled = conf[keys.HealthLowAlphaEnabled] == true
  local belowOnly = conf[keys.HealthCondition] == "BELOW"
  if _G.MSUF_UnitEditModeActive == true or (not lowAlphaEnabled and not belowOnly) then
    SetHolderAlpha(holder, baseAlpha)
    return
  end
  local belowAlpha = lowAlphaEnabled and Clamp01(conf[keys.HealthLowAlpha], 1) or baseAlpha
  local aboveAlpha = belowOnly and 0 or baseAlpha
  local threshold = HealthThreshold(conf, keys)
  local pct = PlainHealthPercent(hp, maxHP)
  if pct ~= nil then
    SetHolderAlpha(holder, pct < threshold and belowAlpha or aboveAlpha)
    return
  end
  local curve = EnsureHealthAlphaCurve(holder, threshold, belowAlpha, aboveAlpha)
  local evaluated = EvaluateUnitCurve(unit, curve)
  if issecretvalue(evaluated) == true or type(evaluated) == "number" then
    SetHolderAlpha(holder, evaluated)
  else
    SetHolderAlpha(holder, baseAlpha)
  end
end

local function ResolveAboveThresholdRGB(conf, keys, unit)
  if conf[keys.HealthAboveMode] == "CLASS" then
    local r, g, b = ResolveClassRGB(unit)
    if r then return r, g, b end
  end
  return Clamp01(conf[keys.ColorR], 1), Clamp01(conf[keys.ColorG], 1), Clamp01(conf[keys.ColorB], 1)
end

local function EnsureThresholdColorCurve(holder, frame, conf, keys, unit)
  if not (holder and CurveAPI and CurveAPI.CreateColorCurve and CreateColor and PreviewHealthGradientColor) then return nil end
  local health = frame.MSUFSpec and frame.MSUFSpec.health
  local threshold = HealthThreshold(conf, keys)
  local aboveMode = conf[keys.HealthAboveMode]
  if aboveMode ~= "CLASS" and aboveMode ~= "CUSTOM" then return nil end
  local fr, fg, fb = ResolveAboveThresholdRGB(conf, keys, unit)
  if holder._msufTexLayerHealthColorCurve
    and holder._msufTexLayerHealthColorSpec == health
    and holder._msufTexLayerHealthColorThreshold == threshold
    and holder._msufTexLayerHealthAboveMode == aboveMode
    and holder._msufTexLayerHealthFallbackR == fr
    and holder._msufTexLayerHealthFallbackG == fg
    and holder._msufTexLayerHealthFallbackB == fb then
    return holder._msufTexLayerHealthColorCurve
  end

  local edge = threshold - 0.0001
  if edge < 0 then edge = 0 end
  local lr, lg, lb = PreviewHealthGradientColor(health, 0)
  local er, eg, eb = PreviewHealthGradientColor(health, edge)
  local curve = CurveAPI.CreateColorCurve()
  if not curve then return nil end
  curve:AddPoint(0, CreateColor(lr, lg, lb, 1))
  if edge > 0.5 then
    local mr, mg, mb = PreviewHealthGradientColor(health, 0.5)
    curve:AddPoint(0.5, CreateColor(mr, mg, mb, 1))
  end
  if edge > 0 then curve:AddPoint(edge, CreateColor(er, eg, eb, 1)) end
  curve:AddPoint(threshold, CreateColor(fr, fg, fb, 1))
  if threshold < 1 then curve:AddPoint(1, CreateColor(fr, fg, fb, 1)) end
  holder._msufTexLayerHealthColorCurve = curve
  holder._msufTexLayerHealthColorSpec = health
  holder._msufTexLayerHealthColorThreshold = threshold
  holder._msufTexLayerHealthAboveMode = aboveMode
  holder._msufTexLayerHealthFallbackR = fr
  holder._msufTexLayerHealthFallbackG = fg
  holder._msufTexLayerHealthFallbackB = fb
  return curve
end

local function ResolveHealthRGB(holder, frame, conf, keys, unit, hp, maxHP, r, g, b)
  local health = frame.MSUFSpec and frame.MSUFSpec.health
  local aboveMode = conf[keys.HealthAboveMode]
  if aboveMode ~= "CLASS" and aboveMode ~= "CUSTOM" then
    if issecretvalue(r) == true or r ~= nil then return r, g, b end
    if hp ~= nil and maxHP ~= nil and HealthGradientColorFromValues then
      r, g, b = HealthGradientColorFromValues(health, hp, maxHP)
      if issecretvalue(r) == true or r ~= nil then return r, g, b end
    end
    if GradientColor then return GradientColor(unit, nil, frame) end
    return nil
  end

  local pct = PlainHealthPercent(hp, maxHP)
  if pct ~= nil then
    if pct >= HealthThreshold(conf, keys) then return ResolveAboveThresholdRGB(conf, keys, unit) end
    if issecretvalue(r) == true or r ~= nil then return r, g, b end
    if hp ~= nil and maxHP ~= nil and HealthGradientColorFromValues then
      r, g, b = HealthGradientColorFromValues(health, hp, maxHP)
      if r ~= nil then return r, g, b end
    end
  end
  local curve = EnsureThresholdColorCurve(holder, frame, conf, keys, unit)
  local color = EvaluateUnitCurve(unit, curve)
  if color and color.GetRGB then return color:GetRGB() end
  if GradientColor then return GradientColor(unit, nil, frame) end
  return ResolveAboveThresholdRGB(conf, keys, unit)
end

local function ApplySlot(frame, conf, unitKey, slot)
  local keys = SLOT_KEYS[slot]
  local prefix = keys.prefix
  local holders = frame._msufTexLayers
  local holder = holders and holders[slot]
  if conf[keys.Enabled] ~= true or not LayerVisible(conf, prefix, frame, unitKey, keys) then
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

  ApplyLayerStrata(frame, holder, conf[keys.Strata])
  if holder.SetFrameLevel and frame.GetFrameLevel then
    local offset = tonumber(conf[keys.Level]) or 1
    if offset < 0 then offset = 0 elseif offset > 30 then offset = 30 end
    local level = Layers.ElementLevel and Layers.ElementLevel(offset, 1, 0)
      or ((frame:GetFrameLevel() or 0) + offset)
    if holder._msufTexLayerLevel ~= level then
      holder:SetFrameLevel(level)
      holder._msufTexLayerLevel = level
    end
  end

  -- Alpha: the frame lane (range fade, ooc fade) is inherited from the parent
  -- unless the user detaches the layer from it; the layer's own alpha always
  -- applies on top.
  if holder.SetIgnoreParentAlpha then
    holder:SetIgnoreParentAlpha(conf[keys.FollowFrameAlpha] == false)
  end
  -- Placement: anchor to the frame or one of its elements.
  local anchorMode = conf[keys.AnchorTarget]
  local target = ResolveAnchorTarget(frame, anchorMode)
  local point = conf[keys.Anchor]
  if not VALID_POINTS[point] then point = "TOP" end
  local width = tonumber(conf[keys.Width]) or 0
  if width <= 0 then
    width = (target.GetWidth and target:GetWidth()) or (frame.GetWidth and frame:GetWidth()) or 100
    if issecretvalue(width) == true or not width or width < 1 then width = 100 end
  end
  local height = tonumber(conf[keys.Height])
  if height == nil then height = 16 end
  if height <= 0 then
    height = (target.GetHeight and target:GetHeight()) or (frame.GetHeight and frame:GetHeight()) or 16
    if issecretvalue(height) == true or not height or height < 1 then height = 16 end
  end
  holder:SetSize(width, height)
  holder:ClearAllPoints()
  holder:SetPoint(point, target, point, tonumber(conf[keys.OffsetX]) or 0, tonumber(conf[keys.OffsetY]) or 0)

  local clipWanted = WantsRoundedClip(conf, prefix, keys)
  local tex = EnsureBaseTexture(holder, clipWanted)
  tex:SetTexture(ResolveLayerTexture(conf, prefix, keys))
  ApplyColorTreatment(tex, conf, prefix, keys)
  if tex.SetBlendMode then
    tex:SetBlendMode(conf[keys.BlendMode] == "ADD" and "ADD" or "BLEND")
  end
  if tex.SetTexCoord then
    tex:SetTexCoord(ResolveTexCoords(conf, prefix, keys))
  end

  local colorMode = conf[keys.ColorMode]
  local r, g, b
  if colorMode == "CLASS" then
    r, g, b = ResolveClassRGB(unitKey)
  elseif colorMode == "HEALTH" then
    r, g, b = ResolveHealthRGB(holder, frame, conf, keys, unitKey)
  end
  if issecretvalue(r) ~= true and not r then
    r = Clamp01(conf[keys.ColorR], 1)
    g = Clamp01(conf[keys.ColorG], 1)
    b = Clamp01(conf[keys.ColorB], 1)
  end
  if colorMode == "HEALTH" then
    ApplyHealthBaseColor(holder, tex, r, g, b)
  else
    ApplyBaseColor(holder, tex, r, g, b)
  end
  ApplyClip(frame, holder, tex, clipWanted)
  local featherTextures = holder._msufTexLayerFeatherTextures
  if not featherTextures then
    featherTextures = {}
    holder._msufTexLayerFeatherTextures = featherTextures
  end
  featherTextures[1] = tex
  local featherCount = 1

  -- Bars-style multi-direction gradient: one WHITE8 overlay per active edge,
  -- fading from transparent to the gradient end color toward that edge.
  local gradientOn = conf[keys.GradientEnabled] == true
  local r2 = Clamp01(conf[keys.Gradient2R], 0)
  local g2 = Clamp01(conf[keys.Gradient2G], 0)
  local b2 = Clamp01(conf[keys.Gradient2B], 0)
  for direction, suffix in pairs(GRADIENT_DIR_SUFFIXES) do
    local value = conf[keys[suffix]]
    local active = gradientOn and (direction == "right" and value ~= false or value == true)
    if active then
      local overlay = EnsureOverlayTexture(holder, direction, clipWanted)
      local orientation = (direction == "up" or direction == "down") and "VERTICAL" or "HORIZONTAL"
      local minA, maxA = 0, 1
      if direction == "left" or direction == "down" then minA, maxA = 1, 0 end
      if overlay.SetGradient and CreateColor then
        local minColor = overlay._msufTexLayerMinColor
        if not minColor then
          minColor = CreateColor(r2, g2, b2, minA)
          overlay._msufTexLayerMinColor = minColor
        elseif minColor.SetRGBA then
          minColor:SetRGBA(r2, g2, b2, minA)
        else
          minColor.r, minColor.g, minColor.b, minColor.a = r2, g2, b2, minA
        end
        local maxColor = overlay._msufTexLayerMaxColor
        if not maxColor then
          maxColor = CreateColor(r2, g2, b2, maxA)
          overlay._msufTexLayerMaxColor = maxColor
        elseif maxColor.SetRGBA then
          maxColor:SetRGBA(r2, g2, b2, maxA)
        else
          maxColor.r, maxColor.g, maxColor.b, maxColor.a = r2, g2, b2, maxA
        end
        overlay:SetGradient(orientation, minColor, maxColor)
      elseif overlay.SetVertexColor then
        overlay:SetVertexColor(r2, g2, b2, 0.5)
      end
      ApplyClip(frame, holder, overlay, clipWanted)
      featherCount = featherCount + 1
      featherTextures[featherCount] = overlay
      overlay:Show()
    else
      local overlay = holder.grads and holder.grads[direction]
      if overlay then overlay:Hide() end
    end
  end
  for i = featherCount + 1, #featherTextures do featherTextures[i] = nil end
  ApplySoftEdgeMask(holder, featherTextures, conf[keys.EdgeSoftness])
  holder.clipApplied = clipWanted or nil
  holder:Show()
  ApplyHealthVisibility(holder, conf, keys, unitKey)
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

local function ApplySlotMask(frame, conf, unitKey, mask)
  if mask == 1 then
    ApplySlot(frame, conf, unitKey, 1)
  elseif mask == 2 then
    ApplySlot(frame, conf, unitKey, 2)
  elseif mask == 3 then
    ApplySlot(frame, conf, unitKey, 1)
    ApplySlot(frame, conf, unitKey, 2)
  elseif mask == 4 then
    ApplySlot(frame, conf, unitKey, 3)
  elseif mask == 5 then
    ApplySlot(frame, conf, unitKey, 1)
    ApplySlot(frame, conf, unitKey, 3)
  elseif mask == 6 then
    ApplySlot(frame, conf, unitKey, 2)
    ApplySlot(frame, conf, unitKey, 3)
  elseif mask == 7 then
    ApplySlot(frame, conf, unitKey, 1)
    ApplySlot(frame, conf, unitKey, 2)
    ApplySlot(frame, conf, unitKey, 3)
  end
end

-- Dynamic-unit class changes do not alter layout, texture, masks, visibility,
-- alpha, or gradients. Keep those events on a color-only path after the cold
-- apply has created the holder; a hidden/uncreated layer will be fully applied
-- by its own visibility event later.
local function ApplyClassColorSlot(frame, conf, unitKey, slot)
  local keys = SLOT_KEYS[slot]
  if conf[keys.Enabled] ~= true then return end
  local colorMode = conf[keys.ColorMode]
  if colorMode == "HEALTH" and conf[keys.HealthAboveMode] == "CLASS" then
    -- A retarget can change the fallback class. Rebuild this single slot on the
    -- rare identity event; health ticks continue through the compiled callback.
    ApplySlot(frame, conf, unitKey, slot)
    return
  end
  if colorMode ~= "CLASS" then return end
  local holders = frame._msufTexLayers
  local holder = holders and holders[slot]
  local tex = holder and holder.tex
  if not tex then return end
  if holder.IsShown and holder:IsShown() ~= true then return end
  local r, g, b = ResolveClassRGB(unitKey)
  if not r then
    r = Clamp01(conf[keys.ColorR], 1)
    g = Clamp01(conf[keys.ColorG], 1)
    b = Clamp01(conf[keys.ColorB], 1)
  end
  if holder._msufTexLayerBaseR == r
    and holder._msufTexLayerBaseG == g
    and holder._msufTexLayerBaseB == b then return end
  ApplyBaseColor(holder, tex, r, g, b)
end

local function ApplyClassColorMask(frame, conf, unitKey, mask)
  if mask == 1 then
    ApplyClassColorSlot(frame, conf, unitKey, 1)
  elseif mask == 2 then
    ApplyClassColorSlot(frame, conf, unitKey, 2)
  elseif mask == 3 then
    ApplyClassColorSlot(frame, conf, unitKey, 1)
    ApplyClassColorSlot(frame, conf, unitKey, 2)
  elseif mask == 4 then
    ApplyClassColorSlot(frame, conf, unitKey, 3)
  elseif mask == 5 then
    ApplyClassColorSlot(frame, conf, unitKey, 1)
    ApplyClassColorSlot(frame, conf, unitKey, 3)
  elseif mask == 6 then
    ApplyClassColorSlot(frame, conf, unitKey, 2)
    ApplyClassColorSlot(frame, conf, unitKey, 3)
  elseif mask == 7 then
    ApplyClassColorSlot(frame, conf, unitKey, 1)
    ApplyClassColorSlot(frame, conf, unitKey, 2)
    ApplyClassColorSlot(frame, conf, unitKey, 3)
  end
end

local function ApplyHealthStateSlot(frame, conf, unit, slot, hp, maxHP, r, g, b)
  local keys = SLOT_KEYS[slot]
  if conf[keys.Enabled] ~= true then return end
  local holders = frame._msufTexLayers
  local holder = holders and holders[slot]
  local tex = holder and holder.tex
  if not tex or (holder.IsShown and holder:IsShown() ~= true) then return end
  if conf[keys.ColorMode] == "HEALTH" then
    local cr, cg, cb = ResolveHealthRGB(holder, frame, conf, keys, unit, hp, maxHP, r, g, b)
    if issecretvalue(cr) == true or cr ~= nil then ApplyHealthBaseColor(holder, tex, cr, cg, cb) end
  end
  ApplyHealthVisibility(holder, conf, keys, unit, hp, maxHP)
end

ApplyHealthStateFrame = function(frame, unit, hp, maxHP, r, g, b)
  local mask = frame and frame._msufTexLayerHealthMask
  if not mask then return end
  local unitKey = frame.MSUFUnitKey
  local conf = unitKey and ConfForUnitKey(unitKey)
  if not conf then return end
  unit = unit or unitKey
  if frame._msufTexLayerHealthColorMask and issecretvalue(r) ~= true and r == nil
    and HealthGradientColorFromValues then
    r, g, b = HealthGradientColorFromValues(frame.MSUFSpec and frame.MSUFSpec.health, hp, maxHP)
  end
  if frame._msufTexLayerHealthDirectGradientMask and issecretvalue(r) ~= true and r == nil and GradientColor then
    r, g, b = GradientColor(unit, nil, frame)
  end
  if mask == 1 then
    ApplyHealthStateSlot(frame, conf, unit, 1, hp, maxHP, r, g, b)
  elseif mask == 2 then
    ApplyHealthStateSlot(frame, conf, unit, 2, hp, maxHP, r, g, b)
  elseif mask == 3 then
    ApplyHealthStateSlot(frame, conf, unit, 1, hp, maxHP, r, g, b)
    ApplyHealthStateSlot(frame, conf, unit, 2, hp, maxHP, r, g, b)
  elseif mask == 4 then
    ApplyHealthStateSlot(frame, conf, unit, 3, hp, maxHP, r, g, b)
  elseif mask == 5 then
    ApplyHealthStateSlot(frame, conf, unit, 1, hp, maxHP, r, g, b)
    ApplyHealthStateSlot(frame, conf, unit, 3, hp, maxHP, r, g, b)
  elseif mask == 6 then
    ApplyHealthStateSlot(frame, conf, unit, 2, hp, maxHP, r, g, b)
    ApplyHealthStateSlot(frame, conf, unit, 3, hp, maxHP, r, g, b)
  elseif mask == 7 then
    ApplyHealthStateSlot(frame, conf, unit, 1, hp, maxHP, r, g, b)
    ApplyHealthStateSlot(frame, conf, unit, 2, hp, maxHP, r, g, b)
    ApplyHealthStateSlot(frame, conf, unit, 3, hp, maxHP, r, g, b)
  end
end

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
  for i = 1, #DYNAMIC_MASK_FIELDS do
    local field = DYNAMIC_MASK_FIELDS[i]
    local list = dynamicFrameLists[field]
    for index = 1, dynamicFrameCounts[field] do list[index] = nil end
    dynamicFrameCounts[field] = 0
  end
  for _, frame in pairs(frames) do
    if frame and frame._msufIsGroupFrame ~= true then
      local unitKey = frame.MSUFUnitKey
      local conf = unitKey and ConfForUnitKey(unitKey)
      if conf then
        CompileDynamicMasks(frame, unitKey, conf)
        for i = 1, #DYNAMIC_MASK_FIELDS do
          local field = DYNAMIC_MASK_FIELDS[i]
          if frame[field] then
            local count = dynamicFrameCounts[field] + 1
            dynamicFrameCounts[field] = count
            dynamicFrameLists[field][count] = frame
          end
        end
      else
        for i = 1, #DYNAMIC_MASK_FIELDS do frame[DYNAMIC_MASK_FIELDS[i]] = nil end
        frame._msufTexLayerHealthMask = nil
        frame._msufTexLayerHealthColorMask = nil
        frame._msufTexLayerHealthDirectGradientMask = nil
        frame._msufTexLayerHealthUpdate = nil
      end
    end
  end
  SyncDriverEvents()
end

local function RefreshDynamicMask(maskField, colorOnly)
  local frames = dynamicFrameLists[maskField]
  local count = dynamicFrameCounts[maskField] or 0
  if not frames or count == 0 then return false end
  for i = 1, count do
    local frame = frames[i]
    local mask = frame[maskField]
    if mask then
      local unitKey = frame.MSUFUnitKey
      local conf = unitKey and ConfForUnitKey(unitKey)
      if conf then
        if colorOnly then
          ApplyClassColorMask(frame, conf, unitKey, mask)
        else
          ApplySlotMask(frame, conf, unitKey, mask)
        end
      end
    end
  end
  return true
end

RefreshDynamicTextureLayers = function(maskField, colorMaskField)
  local refreshed = RefreshDynamicMask(maskField, false)
  if colorMaskField and RefreshDynamicMask(colorMaskField, true) then refreshed = true end
  return refreshed
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
  -- Recompute from every applied frame even after a scoped refresh. This both
  -- registers a newly-enabled conditional layer immediately and unregisters
  -- the last such layer without waiting for a later full visual refresh.
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
