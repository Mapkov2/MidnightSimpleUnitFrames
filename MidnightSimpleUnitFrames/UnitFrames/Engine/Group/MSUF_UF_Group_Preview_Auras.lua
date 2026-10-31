--- Pooled group/unit aura artwork. Scene/sample inputs belong to the caller.
local addonName, MSUF = ...
local GF = MSUF.GF
local Style = assert(GF.PreviewStyle, "Group preview requires PreviewStyle")
local EnsureAuraPreview = Style.EnsureAuraPreview
local EnsurePreviewTexture = Style.EnsurePreviewTexture
local InCombat = Style.InCombat
local PREVIEW_QUESTION = Style.PREVIEW_QUESTION
local PREVIEW_WHITE = Style.PREVIEW_WHITE
local PaintIconLayers = Style.PaintIconLayers
local PreviewLayerOn = Style.PreviewLayerOn
local SetShown = Style.SetShown
local SetText = Style.SetText
local VALID_POINTS = Style.VALID_POINTS
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "GroupFrames/Preview")
local AuraPainter = assert(MSUF.Require("MSUF_Auras3", "GroupFrames/Preview").MockAuraPainter)
local Auras = MSUF.Require("MSUF_Auras3", "GroupFrames/Preview")
local CreateFrame = CreateFrame
local floor = math.floor
local max = math.max
local min = math.min
local type = type
local tonumber = tonumber
local tostring = tostring

local PREVIEW_AURA_SAMPLE_LIMIT = 2
local PREVIEW_AURA_LANES = {
  {
    key = "buff",
    textures = {
      "Interface\\Icons\\Spell_Holy_WordFortitude",
      "Interface\\Icons\\Spell_Holy_Renew",
    },
  },
  {
    key = "trackedBuff",
    textures = {
      "Interface\\Icons\\Spell_Holy_PrayerOfMendingtga",
      "Interface\\Icons\\Spell_Holy_PowerWordShield",
    },
  },
  {
    key = "debuff",
    textures = {
      "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
      "Interface\\Icons\\Spell_Shadow_AbominationExplosion",
    },
  },
  {
    key = "external",
    textures = {
      "Interface\\Icons\\Spell_Holy_SealOfProtection",
      "Interface\\Icons\\Spell_Holy_PowerWordShield",
    },
  },
}
local function EnsureFrameAuraLaneHost(frame, key)
  local hosts = frame._msufGFFrameAuraPreviewHosts
  if not hosts then
    hosts = {}
    frame._msufGFFrameAuraPreviewHosts = hosts
  end
  local host = hosts[key]
  if host then return host end
  host = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
  host:EnableMouse(false)
  if host.SetMouseMotionEnabled then host:SetMouseMotionEnabled(false) end
  hosts[key] = host
  return host
end

local function HideFrameAuraPreview(visual)
  if not visual then return end
  visual:Hide()
  if visual._texture then visual._texture:Hide() end
  if visual._swipe then visual._swipe:Hide() end
  if visual._timer then visual._timer:Hide() end
  if visual._stack then visual._stack:Hide() end
  if visual._durationBar then visual._durationBar:Hide() end
  if visual._stealableMarker then visual._stealableMarker:Hide() end
  local A3 = MSUF and MSUF.MSUF_Auras3
  if A3 and type(A3.ApplyIconStylePreview) == "function" then
    A3.ApplyIconStylePreview(visual, nil)
  end
end

local function FrameAuraPreviewOffset(lane, slot)
  local step = tonumber(lane.stepX or lane.step) or ((tonumber(lane.size) or 1) + (tonumber(lane.spacing) or 0))
  if lane.verticalGrowth == true then
    return 0, slot * (lane.stepY or step) * (tonumber(lane.ySign) or -1)
  end
  local perRow = floor((tonumber(lane.perRow) or 1) + 0.5)
  if not (perRow >= 1) then perRow = 1 end
  local column = slot % perRow
  local row = floor(slot / perRow)
  local x = column * step * (tonumber(lane.xSign) or 1)
  local y = row * (lane.stepY or step) * (tonumber(lane.ySign) or -1)
  return x, y
end

local function ApplyFrameAuraPreview(frame, kind, visual, lane, descriptor, slot, sampleIndex, host, reminderPlaced, scene, sample)
  local A3 = Auras
  local size = tonumber(lane.size) or 18
  if not (size >= 1) then size = 1 end
  local initialAnchor = lane.initialAnchor
  if not VALID_POINTS[initialAnchor] then
    initialAnchor = tostring(initialAnchor or "TOPLEFT"):upper()
    if not VALID_POINTS[initialAnchor] then initialAnchor = "TOPLEFT" end
  end
  local x, y = FrameAuraPreviewOffset(lane, slot)
  if kind == "unit" and (lane.padding or 0) > 0 then
    local px, py = Auras.PaddingInset(initialAnchor, lane.padding)
    x, y = x + px, y + py
  end

  visual:ClearAllPoints()
  visual:SetSize(lane.buttonWidth or size, lane.buttonHeight or size)
  visual:SetPoint(initialAnchor, host, initialAnchor, x, y)
  if visual.SetFrameLevel and host.GetFrameLevel then visual:SetFrameLevel((host:GetFrameLevel() or 0) + 1) end
  if visual.SetAlpha then visual:SetAlpha(1) end

  local texture = visual._texture
  local textures = descriptor.textures
  local entries = lane._msufSceneEntries
  local entry = entries and entries[slot + 1]
  texture:SetTexture(entry and entry.icon or textures[((sampleIndex - 1) % #textures) + 1] or PREVIEW_QUESTION)
  local zoom = tonumber(lane.iconZoom) or 100
  if not (zoom < 200) then zoom = 200 elseif zoom < 100 then zoom = 100 end
  texture:SetTexCoord(A3.IconShape.IconTexCoords(zoom, lane.buttonWidth or size, lane.buttonHeight or size))
  -- Alternate custom slots show the reminder's missing state, as in the Options lane preview.
  local missing = reminderPlaced and reminderPlaced.reminderEnabled == true and slot % 2 == 1
  -- Only reminder samples change saturation; clear it when a pooled missing slot is reused.
  local desaturated = missing and reminderPlaced.reminderDesaturate ~= false or false
  if desaturated or visual._sceneReminderDesaturated then texture:SetDesaturated(desaturated) end
  visual._sceneReminderDesaturated = desaturated or nil
  if missing then
    local tint = type(reminderPlaced.reminderColor) == "table" and reminderPlaced.reminderColor
    texture:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1,
      max(0.1, min(1, tonumber(reminderPlaced.reminderAlpha) or 0.45)))
  else
    texture:SetVertexColor(1, 1, 1, 1)
  end

  local swipe, timer, stack, durationBar, dispelBorder = visual._swipe, visual._timer,
    visual._stack, visual._durationBar, visual._dispelBorder
  if swipe then swipe:Hide() end
  if timer then timer:Hide() end
  if stack then stack:Hide() end
  if durationBar then durationBar:Hide() end
  if dispelBorder then dispelBorder:Hide() end
  local barOnly = lane.showDurationBar == true and lane.durationBarDisplay == "BAR_ONLY"
  texture:SetShown(not barOnly)

  local textAlphas = sample and sample.auraTextAlpha
  swipe = PaintIconLayers(visual, lane, size, barOnly, PreviewLayerOn("auraText", scene),
    sampleIndex == 1 and "12" or "8", textAlphas and textAlphas[descriptor.key], sample and sample.font)

  if type(A3.ApplyAuraIconShape) == "function" then
    A3.ApplyAuraIconShape(visual, lane.iconShape, nil, texture, swipe)
  end
  if type(A3.ApplyIconStylePreview) == "function" then
    local selectedValue2
    if not (barOnly) then selectedValue2 = lane.iconStyle end
    A3.ApplyIconStylePreview(visual, selectedValue2, size, lane.iconShape)
  end
  if lane.showAuraBorder == true and not barOnly then
    dispelBorder = EnsurePreviewTexture(visual, "_dispelBorder", "OVERLAY", 5)
    if type(A3.ApplyAuraDispelPreview) == "function"
      and A3.ApplyAuraDispelPreview(dispelBorder, visual, size,
        lane.showAuraSymbol == true and "SYMBOL" or "BORDER", lane.iconShape,
        A3.PreviewDispelTypeForIndex(sampleIndex)) then
      -- Shared renderer stamped the matching shaped/rounded border.
    elseif dispelBorder.SetAtlas then
      local pad = type(A3.NativeAuraDispelBorderPadding) == "function"
        and A3.NativeAuraDispelBorderPadding(size)
        or max(1, floor(size / 6 + 0.5))
      dispelBorder:ClearAllPoints()
      dispelBorder:SetPoint("TOPLEFT", visual, "TOPLEFT", -pad, pad)
      dispelBorder:SetPoint("BOTTOMRIGHT", visual, "BOTTOMRIGHT", pad, -pad)
      dispelBorder:SetAtlas(lane.showAuraSymbol == true
        and "ui-debuff-border-magic-icon" or "ui-debuff-border-magic-noicon", false)
    else
      dispelBorder:ClearAllPoints()
      dispelBorder:SetAllPoints(visual)
      dispelBorder:SetTexture(PREVIEW_WHITE)
      dispelBorder:SetVertexColor(0.2, 0.6, 1, 0.85)
    end
    dispelBorder:Show()
  end
  local marker = visual._stealableMarker
  if marker then marker:Hide() end
  if descriptor.key == "buff" and lane.showStealableMarker == true and slot == 0 and not barOnly then
    marker = EnsurePreviewTexture(visual, "_stealableMarker", "OVERLAY", 5)
    if lane.stealableStyle == "ICON" then
      local markerSize = max(7, floor(size * 0.42 + 0.5))
      marker:ClearAllPoints()
      marker:SetSize(markerSize, markerSize)
      marker:SetPoint("TOPLEFT", visual, "TOPLEFT", 1, -1)
      marker:SetAtlas("RaidFrame-Icon-DebuffMagic", false)
      marker:SetVertexColor(1, 1, 1, 1)
      marker:Show()
    else
      local mode = lane.stealableStyle == "BORDER" and "BORDER" or "SYMBOL"
      if not A3.ApplyAuraDispelPreview(marker, visual, size, mode, lane.iconShape, "Magic", false) then
        -- Classic's shaped painter leaves rectangular samples to the stock atlas.
        local pad = A3.NativeAuraDispelBorderPadding(size)
        marker:ClearAllPoints()
        marker:SetPoint("TOPLEFT", visual, "TOPLEFT", -pad, pad)
        marker:SetPoint("BOTTOMRIGHT", visual, "BOTTOMRIGHT", pad, -pad)
        marker:SetAtlas(mode == "BORDER" and "ui-debuff-border-magic-noicon" or "ui-debuff-border-magic-icon", false)
        marker:SetVertexColor(1, 1, 1, 1)
        marker:Show()
      end
    end
  end
  if frame._msufPreviewScene then
    visual._sceneStaticTimer = sampleIndex == 1 and "12" or "8"
    visual._sceneAuraLane, visual._sceneAuraKind, visual._sceneAuraIndex = lane,
      (descriptor.key == "debuff" or lane.targetDots or (lane.nativeFilter and lane.nativeFilter:find("HARMFUL", 1, true))) and "debuff" or "buff", slot + 1
    visual._scenePandemicStyled = nil
  end
  visual:Show()
  return true
end

function GF.HideFrameAuras(frame)
  local pool = frame and frame._msufGFFrameAuraPreviews
  if pool then
    for i = 1, #pool do HideFrameAuraPreview(pool[i]) end
  end
  local hosts = frame and frame._msufGFFrameAuraPreviewHosts
  if hosts then
    for _, host in pairs(hosts) do host:Hide() end
  end
  return pool ~= nil or hosts ~= nil
end

--- Each preview row carries its own PatchFrameSpec copy of one compiled base
--- spec, so resolving the aura config against the row missed the runtime's
--- per-spec shared cache and recompiled every lane and slot once per row (a
--- 20-row raid build: 20 configs, 80 lane compiles). The lanes and slots the
--- painters below read reach the spec only through these shared references.
--- While the row still mirrors its base, resolve against the base, the path
--- RefreshPreviewAuras and RefreshPreviewSpellIndicators already take. Classic
--- flavors compile group lanes from the whole spec and share no cache, so they
--- keep resolving per row.
local SHARE_PREVIEW_AURA_CONFIG = not MSUF.Client.IsClassic
local function PreviewAuraConfigSpec(frame, compiledSpec)
  if compiledSpec ~= nil or not SHARE_PREVIEW_AURA_CONFIG then return compiledSpec end
  local spec = frame and frame.MSUFSpec
  local base = frame and frame._msufGFSpecBase
  if not (spec and base) or base == spec or base.auras ~= spec.auras
    or base.spellIndicators ~= spec.spellIndicators or base.cornerIndicators ~= spec.cornerIndicators
    or base.portrait ~= spec.portrait or base.dispelSymbol ~= spec.dispelSymbol then
    return nil
  end
  return base
end

local function SceneLaneEntries(frame, lane, descriptor)
  local scene, model = frame._msufPreviewScene, Auras.MenuModel
  if not (scene and scene.auraSampleCount and model) then return end
  if lane._msufSceneEntries == nil then
    local index = descriptor.key:match("^custom(%d)$")
      or ((descriptor.key == "defensivePortrait" or descriptor.key == "targetDotPortrait") and 4)
    local read = model.CustomContainerPreviewEntries or model.CustomContainerSpellEntries
    lane._msufSceneEntries = index and read and read(frame._msufSceneUnit, tonumber(index)) or false
  end
  return lane._msufSceneEntries
end

--- Lay out and paint the stand-ins of the lanes `descriptors` names that `lanes` enables; true when any icon shows.
local function PaintFrameAuraLanes(frame, kind, lanes, descriptors, previewIndex, sampleLimit, scene, sample)
  local used = 0
  previewIndex = max(1, floor((tonumber(previewIndex) or 1) + 0.5))
  for laneIndex = 1, #descriptors do
    local descriptor = descriptors[laneIndex]
    local lane = lanes[descriptor.key]
    local maxCount = max(0, floor((tonumber(lane and lane.max) or 0) + 0.5))
    local host = EnsureFrameAuraLaneHost(frame, descriptor.key)
    if lane and lane.enabled == true and maxCount > 0 and PreviewLayerOn(descriptor.key, scene) then
      local anchor = tostring(lane.anchor or "CENTER"):upper()
      if not VALID_POINTS[anchor] then anchor = "CENTER" end
      host:ClearAllPoints()
      local parent = frame
      if lane.anchorTarget == "portrait" then
        parent = Auras.ResolvePreviewLaneParent and Auras.ResolvePreviewLaneParent(frame, lane)
          or frame.MSUFPortraitHolder or frame
      end
      host:SetPoint(anchor, parent, anchor, tonumber(lane.x) or 0, tonumber(lane.y) or 0)
      host:SetSize(max(1, tonumber(lane.width) or lane.size or 1),
        max(1, tonumber(lane.height) or lane.size or 1))
      if host.SetFrameLevel and frame.GetFrameLevel then
        local layers = MSUF and MSUF.UF and MSUF.UF.Layers or {}
        host:SetFrameLevel(layers.FrameElementLevel and layers.FrameElementLevel(frame, lane.layer, 1, 0)
          or ((frame:GetFrameLevel() or 0) + (tonumber(lane.layer) or 1)))
      end
      if host.SetAlpha then host:SetAlpha(tonumber(lane.alpha) or 1) end
      host:Show()
      local entries = SceneLaneEntries(frame, lane, descriptor)
      local customIndex = kind == "unit" and descriptor.key:match("^custom(%d)$")
      local item = customIndex and Auras.MenuModel.CustomContainerStyleItem(frame._msufSceneUnit, tonumber(customIndex), false)
      local reminderPlaced = item and item.placed
      local sampleCount = min(entries and #entries > 0 and #entries or sampleLimit or PREVIEW_AURA_SAMPLE_LIMIT, maxCount)
      for sampleIndex = 1, sampleCount do
        used = used + 1
        ApplyFrameAuraPreview(frame, kind, EnsureAuraPreview(frame, used, "_msufGFFrameAuraPreviews"),
          lane, descriptor, sampleIndex - 1, sampleIndex + previewIndex + laneIndex, host, reminderPlaced, scene, sample)
      end
    else
      host:Hide()
    end
  end
  local pool = frame._msufGFFrameAuraPreviews
  for i = used + 1, pool and #pool or 0 do HideFrameAuraPreview(pool[i]) end
  return used > 0
end

function GF.PreviewFrameAuras(frame, kind, previewIndex, compiledAuras, compiledSpec, scene, sample)
  if InCombat() then return false end
  if scene == nil then
    scene = frame and frame._msufGFPreviewScene or GF.PreviewScenes.Default[kind]
    sample = scene and not scene.default and scene.sample
  end
  local spec = frame and frame.MSUFSpec
  local auras = compiledAuras or (spec and spec.auras)
  if not (auras and auras.enabled == true) then
    GF.HideFrameAuras(frame)
    return false
  end

  local A3 = MSUF and MSUF.MSUF_Auras3
  local runtimeConfig = A3 and type(A3.ResolveAuraPreviewConfig) == "function"
    and A3.ResolveAuraPreviewConfig(frame, frame.MSUFUnitKey or "player", PreviewAuraConfigSpec(frame, compiledSpec)) or nil
  local lanes = runtimeConfig and runtimeConfig.lanes
  if not lanes then
    GF.HideFrameAuras(frame)
    return false
  end
  return PaintFrameAuraLanes(frame, kind, lanes, PREVIEW_AURA_LANES, previewIndex, nil, scene, sample)
end

local PREVIEW_UNIT_AURA_LANES = { PREVIEW_AURA_LANES[1], PREVIEW_AURA_LANES[3] }
local UNIT_EXTRA_AURA_LANES = { "custom1", "custom2", "custom3", "custom4", "defensivePortrait", "targetDotPortrait" }
for i = 1, #UNIT_EXTRA_AURA_LANES do
  local key = UNIT_EXTRA_AURA_LANES[i]
  PREVIEW_UNIT_AURA_LANES[#PREVIEW_UNIT_AURA_LANES + 1] = { key = key, textures = PREVIEW_AURA_LANES[1].textures }
end

-- The Style tool has always offered a sample while its lane is disabled. Keep that input on the
-- private scene, leaving the runtime config and saved enable/max values untouched.
local STYLE_LANE_FIELDS = { "size", "x", "y", "anchor", "layer", "iconZoom", "iconShape", "perRow", "spacing",
      "stackSize", "stackX", "stackY", "stackAnchor", "cooldownSize", "cooldownX", "cooldownY", "cooldownAnchor",
      "cooldownDecimalSeconds", "showCooldownSwipe", "cooldownSwipeReverse", "showCooldownText", "showDurationBar",
      "durationBarHeight", "durationBarDisplay", "durationBarPosition", "durationBarDirection" }
local function SceneStyleLane(frame, unit, lanes, kind)
  if not kind then return lanes end
  local model = Auras.MenuModel
  local cfg = model.ReadPreviewConfig(unit)
  local index = tonumber(kind:match("^custom(%d)$"))
  local item = index and model.CustomContainer(unit, index, false)
  local portrait = frame.MSUFSpec and frame.MSUFSpec.portrait
  local portraitKey = index == 4 and item and item.portraitIcon == true and portrait
    and (portrait.enabled == true or item.portraitPositionWhenDisabled == true)
    and (unit == "player" and "defensivePortrait" or "targetDotPortrait") or nil
  local source = lanes and lanes[portraitKey or kind]
    or (index and cfg.customMetrics[index] or cfg[kind .. "Metrics"])
  local lane = {}
  for key, value in pairs(source or {}) do lane[key] = value end
  local raw, placed
  if index then
    raw = model.CustomContainerStyleItem and model.CustomContainerStyleItem(unit, index, false)
      or model.CustomContainer(unit, index, false)
    placed = raw and raw.placed or {}
  else
    placed = {}
    for i = 1, #STYLE_LANE_FIELDS do
      local field = STYLE_LANE_FIELDS[i]
      local value = cfg[kind .. field:sub(1, 1):upper() .. field:sub(2)]
      if value ~= nil then placed[field] = value end
    end
    placed.showStacks = cfg[kind .. "ShowStackCount"]
  end
  for key, value in pairs(placed) do if lane[key] == nil then lane[key] = value end end
  lane.enabled, lane.max = true, max(1, tonumber(lane.max or lane.num or placed.max) or 4)
  if (tonumber(source and (source.max or source.num)) or tonumber(placed.max) or 4) <= 0 then lane.max = 4 end
  lane.size, lane.perRow = lane.size or 26, max(1, lane.perRow or 4)
  if portraitKey and not source then
    lane.anchorTarget, lane.anchor, lane.x, lane.y = "portrait", "CENTER", 0, 0
    lane.max, lane.size = 1, portrait.width or portrait.size or 36
  end
  lane.buttonWidth, lane.buttonHeight = lane.buttonWidth or lane.size, lane.buttonHeight or lane.size
  lane.xSign = lane.xSign or (type(lane.growthX) == "number" and lane.growthX or nil)
  lane.ySign = lane.ySign or (type(lane.growthY) == "number" and lane.growthY or nil)
  lane.stepX = lane.stepX or lane.buttonWidth + (lane.spacing or cfg.spacing or 2)
  lane.stepY = lane.stepY or lane.buttonHeight + (lane.spacing or cfg.spacing or 2)
  local growth, wrap = cfg[kind .. "GrowthX"] or placed.growth or "RIGHT", cfg[kind .. "GrowthY"] or "DOWN"
  if not source then
    lane.verticalGrowth = growth == "UP" or growth == "DOWN"
    lane.xSign, lane.ySign = growth:find("LEFT", 1, true) and -1 or 1,
      (growth:find("UP", 1, true) or wrap == "UP") and 1 or -1
    lane.initialAnchor = (lane.ySign == 1 and "BOTTOM" or "TOP") .. (lane.xSign == 1 and "LEFT" or "RIGHT")
  end
  local cols = lane.verticalGrowth and 1 or min(lane.max, lane.perRow)
  local rows = lane.verticalGrowth and lane.max or math.ceil(lane.max / lane.perRow)
  lane.padding = lane.padding or cfg.stylePadding or 0
  lane.width, lane.height = (cols - 1) * lane.stepX + lane.buttonWidth + 2 * lane.padding,
    (rows - 1) * lane.stepY + lane.buttonHeight + 2 * lane.padding
  local result = {}
  for key, value in pairs(lanes or {}) do result[key] = value end
  if portraitKey then result[kind] = nil end
  result[portraitKey or kind] = lane
  return result
end

--- Aura stand-ins of a unit scene frame: the buff and debuff lanes of the unit's compiled aura configuration, painted
--- like a group frame's. The layer filter of the on-screen previews is lifted for the call.
function GF.PreviewUnitFrameAuras(frame, unit, spec, previewIndex)
  if InCombat() then return false end
  local auras = spec and spec.auras
  local A3 = MSUF and MSUF.MSUF_Auras3
  local config = A3 and A3.ResolveAuraPreviewConfig(frame, unit, spec)
  local scene = frame._msufPreviewScene
  if not (auras and auras.enabled == true) and not (scene.sample.auraStyleKey or scene.sample.auraForceStandard) then
    GF.HideFrameAuras(frame)
    GF.HideSpellIndicators(frame)
    frame._msufSceneAuraLanes = nil
    return false
  end
  local lanes = SceneStyleLane(frame, unit, config and config.lanes, scene.sample.auraStyleKey)
  if scene.sample.auraForceStandard then
    lanes = SceneStyleLane(frame, unit, lanes, "buff")
    lanes = SceneStyleLane(frame, unit, lanes, "debuff")
  end
  frame._msufSceneAuraLanes = lanes
  if not lanes then
    GF.HideFrameAuras(frame)
    return false
  end
  local shown = PaintFrameAuraLanes(frame, "unit", lanes, PREVIEW_UNIT_AURA_LANES, previewIndex, frame._msufPreviewScene.auraSampleCount)
  if frame._msufPreviewScene.auraSampleCount then GF.PreviewSpellIndicators(frame, "unit", spec, unit, false) end
  return shown
end

function GF.AnimateUnitFrameAuras(frame, elapsed)
  local visuals = frame._msufGFFrameAuraPreviews
  for i = 1, #(visuals or {}) do
    local visual = visuals[i]
    local lane = visual._sceneAuraLane
    if lane and visual:IsShown() then
      local state = elapsed ~= nil and AuraPainter.AuraState(visual, visual._sceneAuraKind, visual._sceneAuraIndex, lane, elapsed,
        lane.targetDots and 18 or nil, lane.targetDots, lane.targetDots and 0.30 or nil)
      if visual._swipe and lane.showCooldownSwipe then
        AuraPainter.Swipe(visual._swipe, visual, visual:GetWidth(), visual:GetHeight(), state and state.remainingFrac or 0.42,
          lane.cooldownSwipeReverse == true)
      end
      if visual._timer and lane.showCooldownText then visual._timer:SetText(state and state.text or visual._sceneStaticTimer or "8") end
      if visual._stack and lane.showStacks then visual._stack:SetText(state and state.stacks or "2") end
      if Auras.ApplyPandemicVisual and (lane.targetDots or visual._msufA3PandemicRegion) then
        local inWindow = lane.pandemicEnabled == true and visual._sceneAuraIndex == 1
          and (not state or state.pandemicActive ~= false)
        local region = visual._scenePandemicStyled and visual._msufA3PandemicRegion
        if region then
          region:SetShown(inWindow)
        else
          visual._scenePandemicStyled = Auras.ApplyPandemicVisual(visual, lane, inWindow) ~= nil
        end
      end
      if visual._durationBar then
        AuraPainter.DurationBar(visual._durationBar, visual, lane, visual:GetWidth(), visual:GetHeight(), state)
      end
    end
  end
end

--- Refresh only the pooled Aura stand-ins on active Edit Mode group dummies.
--- Menu sliders use this path while dragging so raw DB geometry reaches the
--- dummy frames immediately without reapplying live frames or rebuilding the
--- rest of each preview button. No preview survives combat, and the hard guard
--- keeps this entry point inert even if an external caller races combat entry.
local function RefreshSceneAuras(scene)
  local kind, t = scene.kind, scene.t
  if type(GF.InvalidateCompiledSpecs) == "function" then GF.InvalidateCompiledSpecs(kind) end
  if not t.active[kind] then return false end
  local compile = GF.GetCompiledSpec or GF.CompileSpec
  local spec = type(compile) == "function" and compile(kind) or nil
  local auras = spec and spec.auras
  local frames = t.frames[kind]
  if not (auras and frames) then return false end

  local refreshed = false
  for i = 1, #frames do
    local frame = frames[i]
    if frame and frame.IsShown and frame:IsShown() then
      GF.PreviewFrameAuras(frame, kind, frame._msufGFPreviewIndex or i, auras, spec)
      refreshed = true
    end
  end
  return refreshed
end

-- A refresh without a kind fans out to every preview kind that is active.

GF.PreviewAuras = {
  PreviewAuraConfigSpec = PreviewAuraConfigSpec,
  RefreshSceneAuras = RefreshSceneAuras,
}
