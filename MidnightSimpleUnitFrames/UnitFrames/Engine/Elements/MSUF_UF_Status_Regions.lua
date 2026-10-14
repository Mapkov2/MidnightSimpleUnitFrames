-- UF responsibility owner; dependencies bind once before runtime.
local _, MSUF = ...
MSUF.UFModuleFactories = MSUF.UFModuleFactories or {}

MSUF.UFModuleFactories.StatusRegions = function(
  SetFont, Apply, ApplyText, ApplyTexture, CreateFrame, Layers, MSUF, Media, PixelLayoutRegion, floor, issecretvalue, tonumber,
    AtlasAvailable
)

local function ClampLayer(layer, fallback)
  layer = floor((tonumber(layer) or fallback or 7) + 0.5)
  if layer < 0 then
    return 0
  elseif layer > 30 then
    return 30
  end
  return layer
end

local GetLayerBaseLevel = Layers.BaseFrameLevel

local function EnsureLayerFrame(frame, layer)
  if not frame then
    return nil
  end
  layer = ClampLayer(layer, 7)
  local layers = frame.MSUFStatusLayers
  if not layers then
    layers = {}
    frame.MSUFStatusLayers = layers
  end
  local holder = layers[layer]
  if not holder then
    holder = PixelLayoutRegion(CreateFrame("Frame", nil, frame._msufHealthVisualRoot or frame))
    holder:SetAllPoints(frame)
    holder:EnableMouse(false)
    if holder.SetClipsChildren then
      holder:SetClipsChildren(false)
    end
    layers[layer] = holder
  end
  if holder.SetFrameLevel then
    local level = (Layers.StatusLevel and Layers.StatusLevel(frame, layer, 7)) or (GetLayerBaseLevel(frame) + 10 + layer)
    if holder._msufStatusFrameLevel ~= level then
      holder:SetFrameLevel(level)
      holder._msufStatusFrameLevel = level
    end
  end
  return holder, layer
end

-- Status flags are plain Lua state, so the status runtime writes through the
-- trusted entry; the cache it shares with every other owner is region._msufShown.
local SetShown = Apply.ShownPlain

local function SetTexture(region, texture)
  if region and region._msufStatusTexture ~= texture then
    ApplyTexture(region, texture)
    region._msufStatusTexture = texture
    region._msufStatusAtlas = nil
  end
end

local function SetAtlas(region, atlas)
  if region and region.SetAtlas and region._msufStatusAtlas ~= atlas then
    region:SetAtlas(atlas)
    region._msufStatusAtlas = atlas
    region._msufStatusTexture = nil
    region._aTex = nil
    region._aColorTexture = nil
    region._msufStatusL, region._msufStatusR, region._msufStatusT, region._msufStatusB = nil, nil, nil, nil
  end
end

local function StopRestingFlipbook(tex, resetAtlas)
  if not tex then return end
  local group = tex._msufRestingFlipbook
  if group then
    local playing = tex._msufRestingFlipbookPlaying == true
    if group.IsPlaying then
      playing = group:IsPlaying() == true
    end
    if playing then
      group:Stop()
    end
  end
  tex._msufRestingFlipbookPlaying = nil
  if resetAtlas == true then
    tex._msufRestingFlipbookAtlas = nil
    tex._msufStatusAtlas = nil
  end
end

local function ApplyRestingFlipbook(tex, play)
  if not (tex and tex.SetAtlas and tex.CreateAnimationGroup) then return false end
  if not AtlasAvailable(tex, Media.RESTING_FLIPBOOK_ATLAS) then return false end
  if tex._msufRestingFlipbookAtlas ~= true then
    tex:SetAtlas(Media.RESTING_FLIPBOOK_ATLAS)
    tex._msufRestingFlipbookAtlas = true
    tex._msufStatusAtlas = Media.RESTING_FLIPBOOK_ATLAS
    tex._msufStatusTexture, tex._aTex, tex._aColorTexture = nil, nil, nil
    tex._msufStatusL, tex._msufStatusR, tex._msufStatusT, tex._msufStatusB = nil, nil, nil, nil
  end
  if play == false then
    StopRestingFlipbook(tex)
    return true
  end
  -- Structural StatusIndicators applies configure the texture without owning
  -- its active state. Preserve an existing loop until RestingIndicator says
  -- explicitly whether it should play or stop.
  if play ~= true then return true end
  local group = tex._msufRestingFlipbook
  if not group then
    group = tex:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    group:SetToFinalAlpha(true)
    local flipbook = group:CreateAnimation("FlipBook")
    flipbook:SetSmoothing("NONE")
    flipbook:SetFlipBookRows(7)
    flipbook:SetFlipBookColumns(6)
    flipbook:SetFlipBookFrames(42)
    flipbook:SetDuration(1.5)
    tex._msufRestingFlipbook = group
  end
  local playing = tex._msufRestingFlipbookPlaying == true
  if group.IsPlaying then
    playing = group:IsPlaying() == true
  end
  if not playing then
    group:Play()
  end
  tex._msufRestingFlipbookPlaying = true
  return true
end

MSUF.UFRestingFlipbook = { Apply = ApplyRestingFlipbook, Stop = StopRestingFlipbook }

local function SetTexCoord(region, l, r, t, b)
  if region and region.SetTexCoord
    and (region._msufStatusL ~= l or region._msufStatusR ~= r or region._msufStatusT ~= t or region._msufStatusB ~= b) then
    region:SetTexCoord(l, r, t, b)
    region._msufStatusL, region._msufStatusR, region._msufStatusT, region._msufStatusB = l, r, t, b
  end
end

local function SetText(region, text, raw)
  if not region then
    return
  end
  if issecretvalue(text) == true then
    region._msufStatusText = nil
    ApplyText(region, text)
    return
  end
  if raw == true then
    region._aText = nil
    region._aTextPlain = nil
    region:SetText(text)
    region._msufStatusText = nil
  elseif region._msufStatusText ~= text then
    ApplyText(region, text)
    region._msufStatusText = text
  end
end

--- A per-indicator color is opt-in: only a complete stored triple overrides the
--- frame's resolved font color, so profiles that never set one keep their exact
--- current look. Alpha stays with the shared font text alpha - an indicator owns
--- its hue, not the global text opacity.
local function ApplyTextColor(region, spec, cfg)
  local c = spec and spec.textColor
  local r, g, b, a = c and c.r or 1, c and c.g or 1, c and c.b or 1, c and c.a or 1
  if cfg and cfg.difficultyColor == true then
    -- A difficulty-colored level text is graded per unit by
    -- Runtime.ApplyLevelDifficultyColor; a static write here would fight it on
    -- every layout pass. The layout pass only repaints the band that unit pass
    -- last resolved, so a palette edit applies live without re-reading the
    -- unit. Both writers share the _msufStatusR/G/B/A cache.
    local tier, colors = region and region._msufLevelTier, cfg.difficultyColors
    if not (tier and colors) then return end
    local base = (tier - 1) * 3
    r, g, b = colors[base + 1], colors[base + 2], colors[base + 3]
  else
    if region and region._msufLevelTier then region._msufLevelTier = nil end
    local cr = cfg and cfg.colorR
    if cr then
      local cg, cb = cfg.colorG, cfg.colorB
      if cg and cb then r, g, b = cr, cg, cb end
    end
  end
  if region and region.SetTextColor
    and (region._msufStatusR ~= r or region._msufStatusG ~= g or region._msufStatusB ~= b or region._msufStatusA ~= a) then
    region:SetTextColor(r, g, b, a)
    region._msufStatusR, region._msufStatusG, region._msufStatusB, region._msufStatusA = r, g, b, a
  end
end

local function ApplyLayer(region, layer)
  if not (region and region.SetDrawLayer) then
    return
  end
  local sub = ClampLayer(layer, 7) - 1
  if sub > 7 then sub = 7 end
  if region._msufStatusLayer ~= sub then
    region:SetDrawLayer("OVERLAY", sub)
    region._msufStatusLayer = sub
  end
end

local function NameRelativeAnchor(frame, anchor)
  local name = frame and frame.nameText
  if not name then
    return nil
  end

  local text = frame.MSUFSpec and frame.MSUFSpec.text or nil
  local dots = frame._msufNameDotsFS
  if dots and dots._msufShown == true and text and text.nameShortenDots == true then
    if anchor == "NAMERIGHT" and text.nameShortenSide == "RIGHT" then
      return dots, "LEFT", "RIGHT", 0
    elseif anchor == "NAMELEFT" and text.nameShortenSide ~= "RIGHT" then
      return dots, "RIGHT", "LEFT", 0
    end
  end

  local clip = frame._msufNameInlineClip
  if clip then
    -- The shorten window stays maxChars wide however short the rendered name
    -- is, so its edge only matches the glyphs while the name really overflows
    -- (tracked by the warm fit). Fitting names anchor to the invisible
    -- auto-width twin that mirrors the visible run inside the window.
    local target = clip
    if frame._msufNameCenterClipOverflow ~= true
      and frame._msufNameAnchorTextActive == true and frame._msufNameAnchorText then
      target = frame._msufNameAnchorText
    end
    if anchor == "NAMERIGHT" then
      return target, "LEFT", "RIGHT", 0
    end
    return target, "RIGHT", "LEFT", 0
  end

  -- Bar-anchored name FontStrings span the full health bar, so their region
  -- edge is not the rendered glyph edge. Text layout supplies an invisible,
  -- auto-sized twin for that case. Anchoring directly to its edge lets the UI
  -- engine propagate restricted name geometry without exposing a secret
  -- GetStringWidth() result to Lua.
  local target = frame._msufNameAnchorTextActive == true and frame._msufNameAnchorText or name
  if anchor == "NAMERIGHT" then
    return target, "LEFT", "RIGHT", 0
  end
  return target, "RIGHT", "LEFT", 0
end

local function AnchorRegion(region, frame, cfg)
  if not (region and frame and cfg) then
    return
  end
  local anchor = cfg.anchor or "TOPLEFT"
  local x = tonumber(cfg.x) or 0
  local y = tonumber(cfg.y) or 0
  local target, point, relPoint = frame, anchor, anchor
  if anchor == "NAMERIGHT" or anchor == "NAMELEFT" then
    local nameTarget, namePoint, nameRelPoint, nameX = NameRelativeAnchor(frame, anchor)
    if nameTarget then
      target, point, relPoint = nameTarget, namePoint, nameRelPoint
      x = x + (nameX or 0)
    elseif anchor == "NAMERIGHT" then
      point, relPoint = "RIGHT", "RIGHT"
    else
      point, relPoint = "LEFT", "LEFT"
    end
  end
  if region._msufStatusAnchor ~= anchor or region._msufStatusTarget ~= target
    or region._msufStatusPoint ~= point or region._msufStatusRelPoint ~= relPoint
    or region._msufStatusX ~= x or region._msufStatusY ~= y then
    region:ClearAllPoints()
    region:SetPoint(point, target, relPoint, x, y)
    region._msufStatusAnchor, region._msufStatusTarget = anchor, target
    region._msufStatusPoint, region._msufStatusRelPoint = point, relPoint
    region._msufStatusX, region._msufStatusY = x, y
  end
end

local function LayoutRegion(region, frame, spec, cfg, isText, fontRole)
  if not (region and cfg) then
    return
  end

  if not isText then
    local size = tonumber(cfg.size) or 16
    if region._msufStatusSize ~= size then
      region:SetSize(size, size)
      region._msufStatusSize = size
    end
  else
    SetFont(region, spec, cfg.size, fontRole)
    ApplyTextColor(region, spec, cfg)
    if region.SetJustifyH then
      local anchor = cfg.anchor
      local justify = (anchor == "RIGHT"
        or anchor == "TOPRIGHT"
        or anchor == "BOTTOMRIGHT"
        or anchor == "NAMELEFT") and "RIGHT"
        or ((anchor == "CENTER"
        or anchor == "TOP"
        or anchor == "BOTTOM") and "CENTER"
        or "LEFT")
      if region._msufStatusJustify ~= justify then
        region:SetJustifyH(justify)
        region._msufStatusJustify = justify
      end
    end
    if region.SetJustifyV and region._msufStatusJustifyV ~= "MIDDLE" then
      region:SetJustifyV("MIDDLE")
      region._msufStatusJustifyV = "MIDDLE"
    end
  end
  ApplyLayer(region, cfg.layer)
  local alpha = spec and spec.status and spec.status.alpha or 1
  if region.SetAlpha and region._msufStatusAlpha ~= alpha then
    region:SetAlpha(alpha)
    region._msufStatusAlpha = alpha
  end
  AnchorRegion(region, frame, cfg)
end

local function AdoptRegion(frame, region, layer)
  local holder = EnsureLayerFrame(frame, layer)
  if region and holder and region.GetParent and region:GetParent() ~= holder then
    if region.SetParent then
      region:SetParent(holder)
      region:ClearAllPoints()
      region._msufStatusAnchor, region._msufStatusTarget = nil, nil
      region._msufStatusX, region._msufStatusY = nil, nil
    else
      return nil
    end
  end
  return holder
end

local function EnsureTexture(frame, field, layer)
  local tex = frame[field]
  local holder = AdoptRegion(frame, tex, layer)
  if tex then
    return tex
  end
  tex = PixelLayoutRegion((holder or frame):CreateTexture(nil, "OVERLAY"))
  tex:SetTexture(Media.WHITE)
  tex:Hide()
  frame[field] = tex
  return tex
end

local function EnsureText(frame, field, layer)
  local fs = frame[field]
  local holder = AdoptRegion(frame, fs, layer)
  if fs then
    return fs
  end
  fs = PixelLayoutRegion((holder or frame):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
  fs:Hide()
  frame[field] = fs
  return fs
end

return AdoptRegion, AnchorRegion, ApplyRestingFlipbook, ApplyTextColor, ClampLayer, EnsureText, EnsureTexture, LayoutRegion,
  SetAtlas, SetShown, SetTexCoord, SetText, SetTexture, StopRestingFlipbook
end
