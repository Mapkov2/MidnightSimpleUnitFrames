--- Pooled spell-indicator artwork and frame effects, with explicit sample inputs.
local addonName, MSUF = ...
local GF = MSUF.GF
local Style = assert(GF.PreviewStyle, "Group preview requires PreviewStyle")
local EnsureAuraPreview = Style.EnsureAuraPreview
local EnsurePreviewFontString = Style.EnsurePreviewFontString
local EnsurePreviewTexture = Style.EnsurePreviewTexture
local InCombat = Style.InCombat
local PREVIEW_QUESTION = Style.PREVIEW_QUESTION
local PREVIEW_WHITE = Style.PREVIEW_WHITE
local PaintIconLayers = Style.PaintIconLayers
local PreviewLayerOn = Style.PreviewLayerOn
local SetPreviewFont = Style.SetPreviewFont
local SetShown = Style.SetShown
local SetText = Style.SetText
local ShowPreviewTimer = Style.ShowPreviewTimer
local VALID_POINTS = Style.VALID_POINTS
local Auras = assert(GF.PreviewAuras, "Group preview requires PreviewAuras")
local PreviewAuraConfigSpec = Auras.PreviewAuraConfigSpec
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "GroupFrames/Preview")
local AuraPainter = assert(MSUF.Require("MSUF_Auras3", "GroupFrames/Preview").MockAuraPainter)
local Auras = MSUF.Require("MSUF_Auras3", "GroupFrames/Preview")
local CreateFrame = CreateFrame
local max = math.max
local type = type
local tonumber = tonumber
local tostring = tostring

local function HideSpellFrameEffectPreview(visual)
  local owner = visual and visual._frameEffectOwner
  if not owner then return false end
  local runtime = MSUF and MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.SpellIndicators
  if runtime and type(runtime.HidePreviewFrameEffect) == "function" then
    return runtime.HidePreviewFrameEffect(owner) == true
  end
  owner:Hide()
  return true
end

local function HideSpellIndicatorPreview(visual)
  if not visual then return end
  visual:Hide()
  local effects = Auras.SpellIndicators
  if effects and effects.HidePreviewIconEffect then effects.HidePreviewIconEffect(visual) end
  if visual._msufA3ClassicIconGlow then visual._msufA3ClassicIconGlow:Hide() end
  if visual._texture then visual._texture:Hide() end
  if visual._swipe then visual._swipe:Hide() end
  if visual._timer then visual._timer:Hide() end
  if visual._stack then visual._stack:Hide() end
  if visual._durationBar then visual._durationBar:Hide() end
  HideSpellFrameEffectPreview(visual)
  local A3 = MSUF and MSUF.MSUF_Auras3
  if A3 and type(A3.ApplyIconStylePreview) == "function" then
    A3.ApplyIconStylePreview(visual, nil)
  end
end

--- Full-Frame effect surfaces for the Group preview.  The owner is a child of
--- the preview frame rather than of the icon host, because an effect-only slot
--- (Display as: none) hides that host while the effect must stay visible.
local function EnsureSpellFrameEffectOwner(visual, frame)
  local owner = visual._frameEffectOwner
  if not owner then
    owner = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
    owner:EnableMouse(false)
    if owner.SetMouseMotionEnabled then owner:SetMouseMotionEnabled(false) end
    visual._frameEffectOwner = owner
  elseif owner:GetParent() ~= frame then
    owner:SetParent(frame)
  end
  owner:ClearAllPoints()
  owner:SetAllPoints(frame)
  return owner
end

--- Previews paint through the live renderer, exactly like the UnitFrame preview
--- does.  A second preview-only implementation had already drifted -- it drew
--- Glow as four edges instead of the runtime's radial halo and used its own
--- Pulse alpha and blend modes -- and only one of the two could ever match the
--- frames.  Layer, priority, thickness and colors now come from the single
--- owner, so preview and runtime cannot disagree again.
local function ApplySpellFrameEffectPreview(visual, frame, slot)
  local runtime = MSUF and MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.SpellIndicators
  local effect = slot and slot.frameEffect
  local health = frame and (frame.hpBar or frame.Health or frame.health)
  if not (visual and frame and health and type(effect) == "table"
    and runtime and type(runtime.ApplyPreviewFrameEffect) == "function") then
    HideSpellFrameEffectPreview(visual)
    return false
  end
  return runtime.ApplyPreviewFrameEffect(EnsureSpellFrameEffectOwner(visual, frame),
    effect, frame) == true
end

local function ApplySpellIndicatorPreview(frame, kind, visual, slot, sample)
  local visualType = slot and tostring(slot.visual or "none"):lower() or "none"
  local hiddenVisual = slot and slot.hiddenVisual == true
  local effectShown = ApplySpellFrameEffectPreview(visual, frame, slot)
  if not slot or (visualType == "none" and not effectShown) then
    HideSpellIndicatorPreview(visual)
    return false
  end

  local size = tonumber(slot.size) or 18
  if not (size >= 1) then size = 1 end
  local width = tonumber(slot.width) or size
  if not (width >= 1) then width = 1 end
  local height = tonumber(slot.height) or size
  if not (height >= 1) then height = 1 end
  local anchor = tostring(slot.anchor or "TOPLEFT"):upper()
  if not VALID_POINTS[anchor] then anchor = "TOPLEFT" end
  visual:ClearAllPoints()
  visual:SetSize(width, height)
  visual:SetPoint(anchor, frame, anchor, tonumber(slot.x) or 0, tonumber(slot.y) or 0)
  if visual.SetFrameLevel and frame.GetFrameLevel then
    local layers = MSUF and MSUF.UF and MSUF.UF.Layers or {}
    visual:SetFrameLevel(layers.FrameElementLevel and layers.FrameElementLevel(frame, slot.layer, 9, 1)
      or ((frame:GetFrameLevel() or 0) + (tonumber(slot.layer) or 9)))
  end

  local color = type(slot.color) == "table" and slot.color or nil
  local r = tonumber(color and color[1]) or 0.69
  local g = tonumber(color and color[2]) or 0.50
  local b = tonumber(color and color[3]) or 0.88
  local a = tonumber(color and color[4]) or 1
  local texture = visual._texture
  local swipe, timer, stack, durationBar = visual._swipe, visual._timer,
    visual._stack, visual._durationBar
  local A3 = MSUF and MSUF.MSUF_Auras3
  texture:ClearAllPoints()
  texture:SetAllPoints(visual)
  if swipe then swipe:Hide() end
  if timer then timer:Hide() end
  if stack then stack:Hide() end
  if durationBar then durationBar:Hide() end
  if visualType ~= "icon" and A3 and type(A3.ApplyIconStylePreview) == "function" then
    -- A skinned Spell Icon painted earlier left its shape mask on the texture.
    if visual._msufSkinShape then
      visual._msufSkinShape = nil
      A3.ApplyAuraIconShape(visual, "RECTANGLE", nil, texture, swipe)
    end
    A3.ApplyIconStyleSkinned(visual, nil)
  end

  local barOnly = slot.showDurationBar == true and slot.durationBarDisplay == "BAR_ONLY"
  if hiddenVisual then
    texture:Hide()
  elseif visualType == "bar" then
    texture:SetTexture(PREVIEW_WHITE)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(r * 0.18, g * 0.18, b * 0.18, a * 0.55)
    texture:Show()
    durationBar = EnsurePreviewTexture(visual, "_durationBar", "OVERLAY", 2)
    durationBar:ClearAllPoints()
    local edge = slot.durationBarReverseFill == true and "RIGHT" or "LEFT"
    durationBar:SetPoint("TOP" .. edge, visual, "TOP" .. edge, 0, 0)
    durationBar:SetPoint("BOTTOM" .. edge, visual, "BOTTOM" .. edge, 0, 0)
    durationBar:SetWidth(max(1, width * 0.68))
    durationBar:SetTexture(PREVIEW_WHITE)
    durationBar:SetVertexColor(r, g, b, a)
    durationBar:Show()
    if slot.showCooldownText == true then ShowPreviewTimer(visual, slot, "12", sample and sample.font) end
  elseif visualType == "square" then
    texture:SetTexture(PREVIEW_WHITE)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(r, g, b, a)
    texture:Show()
  elseif visualType == "number" then
    texture:Hide()
    stack = EnsurePreviewFontString(visual, "_stack")
    SetPreviewFont(stack, slot.numberTextSize or size * 0.72, slot.font or (sample and sample.font))
    stack:SetText(slot.stackText or "2")
    stack:SetTextColor(r, g, b, a)
    AuraPainter.PlaceText(stack, visual, "CENTER", 0, 0, "POINT_ONLY")
    stack:Show()
  else
    texture:SetTexture(slot.icon or PREVIEW_QUESTION)
    local zoom = tonumber(slot.iconZoom) or 100
    if not (zoom < 200) then zoom = 200 elseif zoom < 100 then zoom = 100 end
    local inset = A3.IconShape.IconZoomInset(zoom)
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetShown(not barOnly)

    swipe = PaintIconLayers(visual, slot, size, barOnly, true, "12", nil, sample and sample.font)

    if A3 and type(A3.ApplyIconStylePreview) == "function" then
      local selectedValue1
      if not (barOnly) then selectedValue1 = slot.iconStyle end
      -- A skin draws on the Buff icon shape it was picked with (round, rounded
      -- and hex skins set it), so a skinned Spell Icon shows that shape; an
      -- unskinned one keeps the square preview.
      local skinShape = selectedValue1 ~= nil and selectedValue1.skin ~= nil and slot.iconShape or nil
      if skinShape or visual._msufSkinShape then
        visual._msufSkinShape = skinShape
        A3.ApplyAuraIconShape(visual, skinShape or "RECTANGLE", nil, texture, swipe)
      end
      A3.ApplyIconStyleSkinned(visual, selectedValue1, size, skinShape, height, width)
    end
  end

  local effects = Auras.SpellIndicators
  if effects and effects.ApplyPreviewIconEffect then
    if slot.iconEffect == "glow" and visualType == "icon" and not barOnly and not hiddenVisual then
      effects.ApplyPreviewIconEffect(visual, slot)
    else
      effects.HidePreviewIconEffect(visual)
    end
  elseif visualType == "icon" and Auras.ClassicVisuals then
    visual._msufA3IndicatorConfig = nil
    Auras.ClassicVisuals.ApplyIndicatorVisual(visual, slot)
    if (barOnly or hiddenVisual) and visual._msufA3ClassicIconGlow then visual._msufA3ClassicIconGlow:Hide() end
  elseif visual._msufA3ClassicIconGlow then
    visual._msufA3ClassicIconGlow:Hide()
  end
  visual:SetAlpha(tonumber(slot.alpha) or 1)
  visual:SetShown(not hiddenVisual)
  return not hiddenVisual or effectShown
end

-- An editor's selected or not-yet-placed indicator uses the scene's own
-- painter and a separate retained pool. It never joins the live aura registry.
function GF.PreviewSpellSample(frame, owner, slot)
  if InCombat() or not frame then return nil end
  local visual = EnsureAuraPreview(owner, 1, "_msufSpellSamplePool")
  visual:SetParent(frame)
  visual:SetScale(1)
  visual._msufMenuSpellSample = true
  if visual._msufSampleShape and slot.visual ~= "icon" then
    Auras.ApplyAuraIconShape(visual, "RECTANGLE", nil, visual._texture, visual._swipe)
    visual._msufSampleShape = nil
  end
  local scene = frame._msufGFPreviewScene
  ApplySpellIndicatorPreview(frame, "group", visual, slot, scene and not scene.default and scene.sample)
  if slot.visual == "icon" and not (slot.iconStyle and slot.iconStyle.skin) then
    local portrait = frame.MSUFSpec and frame.MSUFSpec.portrait
    local shape = Auras.ResolveAuraIconShape(slot.iconShape, portrait and portrait.shape)
    Auras.ApplyAuraIconShape(visual, shape, nil, visual._texture, visual._swipe)
    visual._msufSampleShape = true
  end
  return visual
end

function GF.HidePreviewSpellSample(visual)
  if not visual then return end
  local effects = Auras.SpellIndicators
  if effects and effects.HidePreviewIconEffect then effects.HidePreviewIconEffect(visual) end
  local root = visual._msufClassicPreviewIconGlow
  local glow = root and root._msufSpellPreviewGlow
  if glow and glow.animation:IsPlaying() then glow.animation:Stop() end
  if root then root:Hide() end
  visual:Hide()
end

function GF.HideSpellIndicators(frame)
  local pool = frame and frame._msufGFSpellIndicatorPreviews
  if not pool then return false end
  for i = 1, #pool do HideSpellIndicatorPreview(pool[i]) end
  return true
end

function GF.PreviewSpellIndicators(frame, kind, compiledSpec, unit, scene, sample)
  if scene == nil then
    scene = frame and frame._msufGFPreviewScene or GF.PreviewScenes.Default[kind]
    sample = scene and not scene.default and scene.sample
  elseif scene == false then
    scene = nil
  end
  if InCombat() then return false end
  local A3 = MSUF and MSUF.MSUF_Auras3
  local runtimeConfig = A3 and type(A3.ResolveAuraPreviewConfig) == "function"
    and A3.ResolveAuraPreviewConfig(frame, unit or (frame and (frame.MSUFUnitKey or "player")), PreviewAuraConfigSpec(frame, compiledSpec)) or nil
  local root = runtimeConfig and runtimeConfig.spellIndicators
  local slots = root and root.slots
  if not (root and root.enabled == true and type(slots) == "table") or not PreviewLayerOn("si", scene) then
    GF.HideSpellIndicators(frame)
    return false
  end

  local used = 0
  for i = 1, #slots do
    local slot = slots[i]
    if slot and slot.enabled == true then
      used = used + 1
      ApplySpellIndicatorPreview(frame, kind, EnsureAuraPreview(frame, used, "_msufGFSpellIndicatorPreviews"), slot, sample)
    end
  end
  local pool = frame._msufGFSpellIndicatorPreviews
  for i = used + 1, pool and #pool or 0 do HideSpellIndicatorPreview(pool[i]) end
  return used > 0
end

--- Refresh only pooled Spell Indicator stand-ins on active Edit Mode dummies.
--- This is a configuration/preview cold path: no aura queries, subscriptions,
--- timers, or idle scripts are installed, and combat exits before invalidation.
local function RefreshSceneSpellIndicators(scene)
  local kind, t = scene.kind, scene.t
  local spellIndicators = GF.SpellIndicators
  if spellIndicators and type(spellIndicators.InvalidateRuntimeCaches) == "function" then
    spellIndicators.InvalidateRuntimeCaches()
  end
  if type(GF.InvalidateCompiledSpecs) == "function" then GF.InvalidateCompiledSpecs(kind) end
  if not t.active[kind] then return false end
  local compile = GF.GetCompiledSpec or GF.CompileSpec
  local spec = type(compile) == "function" and compile(kind) or nil
  local frames = t.frames[kind]
  if not (spec and frames) then return false end

  local refreshed = false
  for i = 1, #frames do
    local frame = frames[i]
    if frame and frame.IsShown and frame:IsShown() then
      GF.PreviewSpellIndicators(frame, kind, spec)
      refreshed = true
    end
  end
  return refreshed
end

GF.PreviewIndicators = {
  RefreshSceneSpellIndicators = RefreshSceneSpellIndicators,
}
