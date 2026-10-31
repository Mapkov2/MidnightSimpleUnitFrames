--- Stateless preview artwork, fonts and layer visibility; callers supply their scene and font.
local addonName, MSUF = ...
local GF = MSUF.GF
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "GroupFrames/Preview")
local AuraPainter = assert(MSUF.Require("MSUF_Auras3", "GroupFrames/Preview").MockAuraPainter)
local Auras = MSUF.Require("MSUF_Auras3", "GroupFrames/Preview")
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local type = type
local tonumber = tonumber

-- Resolve forward/cold exports at use time, preserving the existing dependency boundary.
local function Dep(name)
  return MSUF.Require(name, "UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
end

local VALID_POINTS = {
  CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
  TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

--- The menu's LAYERS rail is the one place a user switches preview elements on
--- and off, so the in-world dummies read the same switches as the docked
--- preview instead of answering a different question about the same profile.
--- Both nil means no menu has spoken yet: everything the settings enable draws.
--- Solo (Shift-click) is exclusive here rather than the menu's 0.15 dimming --
--- these are live frames whose region alpha belongs to the Alpha element.
-- A paint reads its own scene. There is no ambient current scene, filter
-- swap or clock that a nested callback can overwrite.
--- Guides and Bounds are drag-handle chrome that exists only inside the docked
--- preview. Soloing one of those must not blank the in-world dummies, so a solo
--- on a key the dummies do not own is dropped rather than applied.
local PREVIEW_LAYER_KEYS = {
  text = true, power = true, status = true, si = true, auraText = true,
  buff = true, trackedBuff = true, debuff = true, external = true,
}

local function PreviewLayerOn(key, scene)
  if not scene then return true end
  if scene.layerSolo ~= nil then return scene.layerSolo == key end
  return not (scene.layerVisible and scene.layerVisible[key] == false)
end

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

--- Hard dependencies on exports of files that load before this one (the UF
local function PreviewAnimationActive()
  -- The animation module's own flag; the exported accessor (and its missing-dependency error) only without the module.
  local animation = MSUF.PreviewAnimation
  if animation then return animation.IsEnabled() == true end
  return Dep("MSUF_IsPreviewAnimationEnabled")() == true
end
local function SetShown(region, shown)
  if region and region.SetShown then region:SetShown(shown and true or false) end
end

local function SetText(region, text)
  if region and region.SetText then region:SetText(text or "") end
end

--- Native aura elements deliberately stay disabled on synthetic group-preview
--- rows because each Blizzard CustomAuraContainer allocates AuraButtons in
--- batches and can only show the real player's current auras. These tiny
--- addon-owned regions mirror only already-compiled aura/spell placement data
--- on every Party/Raid/Mythic dummy. They are pooled with the preview button,
--- never query UnitAura, and never register an event or OnUpdate.
local PREVIEW_WHITE = "Interface\\Buttons\\WHITE8X8"
local PREVIEW_QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local function SetPreviewFont(fontString, size, font)
  if not (fontString and fontString.SetFont) then return end
  size = tonumber(size) or 10
  if not (size >= 6) then size = 6 end
  local path, flags = font and font.path or STANDARD_TEXT_FONT, font and font.flags or "OUTLINE"
  local alpha, x, y = font and font.shadowAlpha or 0, font and font.shadowX or 0, font and font.shadowY or 0
  if fontString._msufGFPreviewFontSize == size and fontString._msufGFPreviewFontPath == path
    and fontString._msufGFPreviewFontFlags == flags and fontString._msufGFPreviewShadowAlpha == alpha
    and fontString._msufGFPreviewShadowX == x and fontString._msufGFPreviewShadowY == y then return end
  path = Dep("MSUF_ResolveSafeFontPath")(path, size, flags, font and font.key)
  local setFont = Dep("MSUF_SetFontChecked")
  local accepted = setFont(fontString, path, size, flags)
  if not accepted then
    path = STANDARD_TEXT_FONT
    accepted = setFont(fontString, path, size, flags)
  end
  fontString._msufGFPreviewFontSize = accepted and size or nil
  fontString._msufGFPreviewFontPath, fontString._msufGFPreviewFontFlags = accepted and path or nil, flags
  fontString._msufGFPreviewShadowAlpha, fontString._msufGFPreviewShadowX, fontString._msufGFPreviewShadowY = alpha, x, y
  fontString:SetShadowColor(0, 0, 0, alpha)
  fontString:SetShadowOffset(x, y)
end


local function EnsureAuraPreview(frame, index, poolKey)
  local pool = frame[poolKey]
  if not pool then
    pool = {}
    frame[poolKey] = pool
  end
  local visual = pool[index]
  if visual then return visual end

  visual = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
  visual:EnableMouse(false)
  if visual.SetMouseMotionEnabled then visual:SetMouseMotionEnabled(false) end
  visual._texture = PixelLayoutRegion(visual:CreateTexture(nil, "ARTWORK"))
  visual._texture:SetAllPoints(visual)
  pool[index] = visual
  return visual
end

local function EnsurePreviewTexture(visual, key, layer, sublevel)
  local texture = visual[key]
  if not texture then
    texture = PixelLayoutRegion(visual:CreateTexture(nil, layer, nil, sublevel))
    visual[key] = texture
  end
  return texture
end

local function EnsurePreviewFontString(visual, key)
  local fontString = visual[key]
  if not fontString then
    fontString = PixelLayoutRegion(visual:CreateFontString(nil, "OVERLAY"))
    visual[key] = fontString
  end
  return fontString
end

local function ShowPreviewTimer(visual, cfg, text, font)
  local timer = EnsurePreviewFontString(visual, "_timer")
  SetPreviewFont(timer, cfg.cooldownSize or 8, cfg.font or font)
  timer:SetText(text)
  timer:SetTextColor(1, 1, 1, 1)
  AuraPainter.PlaceText(timer, visual, cfg.cooldownAnchor or "CENTER", cfg.cooldownX or 0, cfg.cooldownY or 0, "POINT_ONLY")
  timer:Show()
end

--- Swipe, timer, stack and duration bar of an icon-type lane aura or indicator;
--- both read the same field names. Returns the icon's swipe region, if any.
local function PaintIconLayers(visual, cfg, size, barOnly, textOn, timerText, textAlpha, font)
  if cfg.showCooldownSwipe == true and not barOnly then
    AuraPainter.TopSwipe(EnsurePreviewTexture(visual, "_swipe", "OVERLAY", 1), visual, size, 0.42)
  end
  if cfg.showCooldownText == true and textOn then
    ShowPreviewTimer(visual, cfg, timerText, font)
    visual._timer:SetAlpha(textAlpha or 1)
  end
  if cfg.showStacks == true and textOn then
    local stack = EnsurePreviewFontString(visual, "_stack")
    SetPreviewFont(stack, cfg.stackSize or 10, cfg.font or font)
    stack:SetText(cfg.stackText or "2")
    stack:SetAlpha(textAlpha or 1)
    local r, g, b
    if type(Auras.GetStackCountColor) == "function" then r, g, b = Auras.GetStackCountColor() end
    stack:SetTextColor(r or 1, g or 1, b or 1, 1)
    AuraPainter.PlaceText(stack, visual, cfg.stackAnchor or "BOTTOMRIGHT", cfg.stackX or 0, cfg.stackY or 0, "POINT_ONLY")
    stack:Show()
  end
  if cfg.showDurationBar == true then
    local height = tonumber(cfg.durationBarHeight) or 2
    if not (height < size) then height = size elseif height < 1 then height = 1 end
    AuraPainter.GroupDurationBar(EnsurePreviewTexture(visual, "_durationBar", "OVERLAY", 2), visual, cfg.durationBarPosition, height)
  end
  return visual._swipe
end

GF.PreviewStyle = {
  VALID_POINTS = VALID_POINTS,
  PREVIEW_LAYER_KEYS = PREVIEW_LAYER_KEYS,
  PREVIEW_WHITE = PREVIEW_WHITE,
  PREVIEW_QUESTION = PREVIEW_QUESTION,
  PreviewLayerOn = PreviewLayerOn,
  InCombat = InCombat,
  PreviewAnimationActive = PreviewAnimationActive,
  SetShown = SetShown,
  SetText = SetText,
  SetPreviewFont = SetPreviewFont,
  EnsureAuraPreview = EnsureAuraPreview,
  EnsurePreviewTexture = EnsurePreviewTexture,
  EnsurePreviewFontString = EnsurePreviewFontString,
  ShowPreviewTimer = ShowPreviewTimer,
  PaintIconLayers = PaintIconLayers,
}
