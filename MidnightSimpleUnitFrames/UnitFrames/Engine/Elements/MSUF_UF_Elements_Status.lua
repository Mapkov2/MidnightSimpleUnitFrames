local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local UF = MSUF.UF
if not UF then return end
local Layers = UF.Layers or {}

-- Unitframe status indicator element.
-- Owns level/classification/PvP/ready-check/role/raid-marker style icons for normal unit
-- frames. This is an event-hot path, so helpers prefer cached unit state, secret-safe reads,
-- and cached region mutation instead of rebuilding textures every event.
local CreateFrame = CreateFrame
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitAffectingCombat = UnitAffectingCombat
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitLevel = UnitLevel
local UnitRace = UnitRace
local UnitClassification = UnitClassification or GetUnitClassification
local UnitIsPlayer = UnitIsPlayer
local UnitIsPVP = UnitIsPVP
local UnitIsPVPFreeForAll = UnitIsPVPFreeForAll
local UnitFactionGroup = UnitFactionGroup
local UnitIsMercenary = UnitIsMercenary
local UnitIsGhost = UnitIsGhost
local UnitIsAFK = UnitIsAFK
local UnitIsDND = UnitIsDND
local UnitPhaseReason = UnitPhaseReason
local UnitInRaid = UnitInRaid
local GetRaidRosterInfo = GetRaidRosterInfo
local GetRaidTargetIndex = GetRaidTargetIndex
local GetReadyCheckStatus = GetReadyCheckStatus
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local IsResting = IsResting
local InCombatLockdown = InCombatLockdown
local C_IncomingSummon = C_IncomingSummon
local C_Timer = C_Timer
local GetTime = GetTime
local type = type
local tostring = tostring
local tonumber = tonumber
local floor = math.floor
local find = string.find
local setmetatable = setmetatable
local Secrets = MSUF.Secrets or {}

local issecretvalue = _G.issecretvalue or function(_) return false end
local function BoolTrue(value)
  -- Secret values from restricted APIs must not leak into boolean UI decisions. Treat them as
  -- unknown rather than truthy so protected/hidden state cannot accidentally show an icon.
  if issecretvalue(value) == true then
    return false
  end
  return value == true or value == 1
end
local function SafeNumber(value)
  if issecretvalue(value) == true then
    return nil
  end
  return tonumber(value)
end
local FreshUnitState = UF.FreshUnitState
local ReadConnectedCached = UF.ReadConnectedCached
local ReadDeadCached = UF.ReadDeadCached
local ReadUnitExistsCached = UF.ReadUnitExistsCached
local ReadUnitIsPlayerCached = UF.ReadUnitIsPlayerCached
local ReadUnitClassCached = UF.ReadUnitClassCached
local function UnitExistsRuntime(unit, state, frame)
  if state and state.existsKnown == true then
    return state.exists == true
  end
  local exists = ReadUnitExistsCached(frame, unit)
  return exists == true
end
local function UnitIsPlayerRuntime(unit, state, frame)
  if state and state.isPlayerKnown == true then
    return state.isPlayer == true
  end
  local isPlayer, known = ReadUnitIsPlayerCached(frame, unit)
  if known == true then return isPlayer == true end
  return UnitIsPlayer and false or nil
end
local Apply = MSUF.Apply or {}
local ApplyShown = Apply.Shown or function(region, show)
  if not region then return end
  show = show and true or false
  if region._aShown ~= show then
    region:SetShown(show)
    region._aShown = show
  end
end
local ApplyTexture = Apply.Texture or function(region, texture)
  if not region then return end
  if issecretvalue(texture) == true then
    region._aTex = nil
    region._aColorTexture = nil
    region:SetTexture(texture)
    return
  end
  if region._aTex ~= texture then
    region:SetTexture(texture)
    region._aTex = texture
    region._aColorTexture = nil
  end
end
local ApplyText = Apply.Text or function(region, text)
  if not region then return end
  if issecretvalue(text) == true then
    region._aText = nil
    region._aTextPlain = nil
    region:SetText(text)
    return
  end
  text = text or ""
  if region._aTextPlain == true and region._aText == text then
    return
  end
  region:SetText(text)
  region._aText = text
  region._aTextPlain = true
end

local EMPTY_EVENTS = {}
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ADDON_PATH = "Interface\\AddOns\\" .. (addonName or "MidnightSimpleUnitFrames")
local RAID_MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local LEADER_TEXTURE = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local ASSIST_TEXTURE = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
local READY_TEXTURES = {
  ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
  notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
  waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local READY_REZ_TEXTURE = "Interface\\RaidFrame\\Raid-Icon-Rez"
local PHASE_TEXTURE = "Interface\\TargetingFrame\\UI-PhasingIcon"
local STATE_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon"
local RESTING_ANIMATED_SYMBOL = "rested_blizzard_animated"
local RESTING_FLIPBOOK_ATLAS = "UI-HUD-UnitFrame-Player-Rest-Flipbook"
local PVP_FFA_ATLAS = "UI-HUD-UnitFrame-Player-PVP-FFAIcon"
local PVP_ALLIANCE_ATLAS = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon"
local PVP_HORDE_ATLAS = "UI-HUD-UnitFrame-Player-PVP-HordeIcon"
local PVP_ATLAS_BY_FACTION = { Horde = PVP_HORDE_ATLAS, Alliance = PVP_ALLIANCE_ATLAS }
local PVP_TEXTURE_BY_ATLAS = {
  [PVP_HORDE_ATLAS] = "Interface\\TargetingFrame\\UI-PVP-Horde",
  [PVP_ALLIANCE_ATLAS] = "Interface\\TargetingFrame\\UI-PVP-Alliance",
}
local SYMBOL_BASE = ADDON_PATH .. "\\Media\\Symbols\\"
-- These are the complete symbol identifiers written by native MSUF 5.5.
-- Never synthesize a texture path for an unknown value: WoW renders a missing
-- file assigned to an existing Texture region as an opaque white rectangle.
local VALID_STATE_SYMBOLS = {
  weapon_axes_crossed = true,
  weapon_bows_crossed = true,
  weapon_crossbows_crossed = true,
  weapon_daggers_crossed = true,
  weapon_fishing_poles_crossed = true,
  weapon_fist_crossed = true,
  weapon_guns_crossed = true,
  weapon_maces_crossed = true,
  weapon_polearms_crossed = true,
  weapon_shuriken = true,
  weapon_staves_crossed = true,
  weapon_swords_crossed = true,
  weapon_thrown_crossed = true,
  weapon_wands_crossed = true,
  weapon_warglaives_crossed = true,
  rested_moonzzz = true,
  rested_moonzzzz = true,
  rested_sleep_zzzz = true,
  rested_zzz_compact = true,
  rested_zzz_diag = true,
  rested_zzz_stack = true,
  resurrection_ankh = true,
  resurrection_cross = true,
  resurrection_soul = true,
  resurrection_wings = true,
}
local SUMMON_TEXTURES = {
  [1] = "Interface\\RaidFrame\\Raid-Icon-SummonPending",
  [2] = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted",
  [3] = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined",
}
local STATUS_REFRESH = {
  "StatusIndicators",
  "RaidMarkerIndicator",
  "LeaderIndicator",
  "LevelIndicator",
  "RaidGroupIndicator",
  "EliteIndicator",
  "StatusTextIndicator",
  "CombatIndicator",
  "RestingIndicator",
  "IncomingResIndicator",
  "PVPIndicator",
  "StanceIndicator",
  "GroupStatusRuntime",
}
local SYMBOL_PATH_CACHE = {}
local READY_CHECK_TIMERS = setmetatable({}, { __mode = "k" })
local READY_CHECK_LIST = {}
local READY_CHECK_HEAD = 1
local READY_CHECK_TAIL = 0
local READY_CHECK_TIMER_AT

local Status = {}

local function ClampLayer(layer, fallback)
  layer = floor((tonumber(layer) or fallback or 7) + 0.5)
  if layer < 0 then
    return 0
  elseif layer > 30 then
    return 30
  end
  return layer
end

local function GetLayerBaseLevel(frame)
  local base = frame and (frame.Health or frame.hpBar or frame)
  return base and base.GetFrameLevel and (base:GetFrameLevel() or 0) or 0
end

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
    holder = CreateFrame("Frame", nil, frame)
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

local function SetShown(region, show)
  show = show and true or false
  if region and region._msufStatusShown ~= show then
    ApplyShown(region, show)
    region._msufStatusShown = show
  end
end

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

local function AtlasAvailable(region, atlas)
  if not (region and region.SetAtlas and type(atlas) == "string" and atlas ~= "") then
    return false
  end
  local textureAPI = _G.C_Texture
  if not (textureAPI and type(textureAPI.GetAtlasInfo) == "function") then
    return false
  end
  return textureAPI.GetAtlasInfo(atlas) ~= nil
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
  if not AtlasAvailable(tex, RESTING_FLIPBOOK_ATLAS) then return false end
  if tex._msufRestingFlipbookAtlas ~= true then
    tex:SetAtlas(RESTING_FLIPBOOK_ATLAS)
    tex._msufRestingFlipbookAtlas = true
    tex._msufStatusAtlas = RESTING_FLIPBOOK_ATLAS
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

local function ApplyStatusFont(region, font, size, flags)
  if not (region and region.SetFont and font) then
    return false
  end
  size = tonumber(size) or 14
  if size <= 0 then size = 14 end
  if size < 6 then size = 6 elseif size > 128 then size = 128 end
  local ok, applied = pcall(region.SetFont, region, font, size, flags)
  if not ok or applied == false then return false end
  local matches = _G.MSUF_FontApplicationMatches
  if type(matches) == "function" then
    return matches(region, font, size) == true
  end
  if type(region.GetFont) ~= "function" then return true end
  local actualFont, actualSize = region:GetFont()
  if not actualFont then return false end
  local pathMatches = tostring(actualFont):gsub("/", "\\"):lower() == tostring(font):gsub("/", "\\"):lower()
  actualSize = tonumber(actualSize)
  return pathMatches and actualSize ~= nil and math.abs(actualSize - size) <= 0.01
end

local function SetFont(region, spec, size, role)
  if not region or not region.SetFont then
    return true
  end
  local flags = spec and spec.fontFlags or "OUTLINE"
  size = tonumber(size) or 14
  if size <= 0 then size = 14 end
  if size < 6 then size = 6 elseif size > 128 then size = 128 end
  local font = spec and spec.font
  local resolveRoleFont = MSUF.UFText and MSUF.UFText.ResolveRoleFont
  if role and type(resolveRoleFont) == "function" then
    font = resolveRoleFont(font, role, size)
  end
  local fontEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
  local fontReady = region._msufStatusFontPending ~= true
  if font and (region._msufStatusFontAttemptEpoch ~= fontEpoch
      or region._msufStatusFont ~= font
      or region._msufStatusFontSize ~= size
      or region._msufStatusFontFlags ~= flags)
  then
    if ApplyStatusFont(region, font, size, flags) then
      region._msufStatusFont, region._msufStatusFontSize, region._msufStatusFontFlags = font, size, flags
      region._msufStatusFontEpoch = fontEpoch
      region._msufStatusFontAttemptEpoch = fontEpoch
      region._msufStatusFontPending = nil
      fontReady = true
    else
      local clear = _G.MSUF_ClearFontStringApplyCaches
      if type(clear) == "function" then clear(region) end
      region._msufStatusFont, region._msufStatusFontSize, region._msufStatusFontFlags = font, size, flags
      region._msufStatusFontEpoch = nil
      region._msufStatusFontAttemptEpoch = fontEpoch
      region._msufStatusFontPending = true
      local markFailed = _G.MSUF_MarkFontApplyFailed
      if type(markFailed) == "function" then markFailed() end
      fontReady = false
    end
  end
  if region.SetShadowOffset then
    local shadowOn = spec and spec.fontShadow == true
    local sx = shadowOn and (tonumber(spec and spec.fontShadowX) or 1) or 0
    local sy = shadowOn and (tonumber(spec and spec.fontShadowY) or -1) or 0
    local sa = shadowOn and (tonumber(spec and spec.fontShadowAlpha) or 1) or 0
    if region._msufStatusShadowX ~= sx or region._msufStatusShadowY ~= sy or region._msufStatusShadowA ~= sa then
      if shadowOn and region.SetShadowColor then region:SetShadowColor(0, 0, 0, sa) end
      region:SetShadowOffset(sx, sy)
      region._msufStatusShadowX, region._msufStatusShadowY, region._msufStatusShadowA = sx, sy, sa
    end
  end
  return fontReady
end

--- A per-indicator color is opt-in: only a complete stored triple overrides the
--- frame's resolved font color, so profiles that never set one keep their exact
--- current look. Alpha stays with the shared font text alpha - an indicator owns
--- its hue, not the global text opacity.
local function ApplyTextColor(region, spec, cfg)
  local c = spec and spec.textColor
  local r, g, b, a = c and c.r or 1, c and c.g or 1, c and c.b or 1, c and c.a or 1
  local cr = cfg and cfg.colorR
  if cr then
    local cg, cb = cfg.colorG, cfg.colorB
    if cg and cb then r, g, b = cr, cg, cb end
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
      local justify = (anchor == "RIGHT" or anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT" or anchor == "NAMELEFT") and "RIGHT" or ((anchor == "CENTER" or anchor == "TOP" or anchor == "BOTTOM") and "CENTER" or "LEFT")
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
  tex = (holder or frame):CreateTexture(nil, "OVERLAY")
  tex:SetTexture(WHITE)
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
  fs = (holder or frame):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:Hide()
  frame[field] = fs
  return fs
end

local function SymbolPath(symbol, useMidnight)
  if type(symbol) ~= "string" or symbol == "" or symbol == "DEFAULT" then
    return nil
  end
  if not VALID_STATE_SYMBOLS[symbol] then
    return nil
  end
  local cacheKey = symbol .. (useMidnight and "\001M" or "\001C")
  local cached = SYMBOL_PATH_CACHE[cacheKey]
  if cached then
    return cached
  end
  local folder = "Combat"
  local suffix = useMidnight and "_midnight_128_clean.tga" or "_classic_128_clean.tga"
  if find(symbol, "^rested_") then
    folder = "Rested"
    suffix = useMidnight and "_midnight_64.tga" or "_classic_64.tga"
  elseif find(symbol, "^resurrection_") then
    folder = "Ress"
    suffix = useMidnight and "_midnight_64.tga" or "_classic_64.tga"
  end
  local path = SYMBOL_BASE .. folder .. "\\" .. symbol .. suffix
  SYMBOL_PATH_CACHE[cacheKey] = path
  return path
end

local function ApplyStateIconTexture(tex, kind, cfg, status)
  local path = SymbolPath(cfg and cfg.symbol, status and status.useMidnight == true)
  if path then
    SetTexture(tex, path)
    SetTexCoord(tex, 0, 1, 0, 1)
    return
  end
  if kind == "combat" then
    if AtlasAvailable(tex, "UI-HUD-UnitFrame-Player-PortraitCombatIcon") then
      SetAtlas(tex, "UI-HUD-UnitFrame-Player-PortraitCombatIcon")
    else
      SetTexture(tex, STATE_TEXTURE)
      SetTexCoord(tex, 0.5, 1, 0, 0.5)
    end
  elseif kind == "resting" then
    SetTexture(tex, STATE_TEXTURE)
    SetTexCoord(tex, 0, 0.5, 0, 0.5)
  elseif kind == "incomingRes" then
    SetTexture(tex, READY_REZ_TEXTURE)
    SetTexCoord(tex, 0, 1, 0, 1)
  end
end

local function PVPAtlasForFaction(factionGroup)
  return PVP_ATLAS_BY_FACTION[factionGroup]
end

local function PVPFallbackTextureForAtlas(atlas)
  return PVP_TEXTURE_BY_ATLAS[atlas]
end

local function ResolvePVPAtlas(frame, unit, unitState)
  if not (unit and UnitExistsRuntime(unit, unitState, frame)) then
    return nil
  end
  if UnitIsPVPFreeForAll and BoolTrue(UnitIsPVPFreeForAll(unit)) then
    return PVP_FFA_ATLAS
  end
  if not (UnitIsPVP and UnitFactionGroup and BoolTrue(UnitIsPVP(unit))) then
    return nil
  end
  local factionGroup = UnitFactionGroup(unit)
  if issecretvalue(factionGroup) == true or not factionGroup or factionGroup == "Neutral" then
    return nil
  end
  if unit == "player" and UnitIsMercenary and BoolTrue(UnitIsMercenary(unit)) then
    if factionGroup == "Horde" then
      factionGroup = "Alliance"
    elseif factionGroup == "Alliance" then
      factionGroup = "Horde"
    end
  end
  return PVPAtlasForFaction(factionGroup)
end

local function ResolvePVPTestAtlas(unit)
  local factionGroup
  if UnitFactionGroup then
    factionGroup = UnitFactionGroup("player")
  end
  if issecretvalue(factionGroup) == true then
    factionGroup = nil
  end
  return PVPAtlasForFaction(factionGroup) or PVP_ALLIANCE_ATLAS
end

local function ApplyPVPTexture(tex, atlas)
  if not (tex and atlas) then
    return false
  end
  if tex.SetAtlas then
    SetAtlas(tex, atlas)
    return true
  end
  local fallback = PVPFallbackTextureForAtlas(atlas)
  if fallback then
    SetTexture(tex, fallback)
    SetTexCoord(tex, 0, 1, 0, 1)
    return true
  end
  return false
end

local function ApplyLeaderTexture(tex, cfg, status, assist)
  if cfg and type(cfg.customIcon) == "string" and cfg.customIcon ~= "" then
    SetTexture(tex, cfg.customIcon)
    SetTexCoord(tex, 0, 1, 0, 1)
    return
  end
  local gf = MSUF and MSUF.GF
  local kind = status and status.kind
  if gf and kind then
    local resolver = assist and gf.GetAssistTexture or gf.GetLeaderTexture
    if type(resolver) == "function" then
      local path, l, r, t, b = resolver(kind, cfg and cfg.style)
      if type(path) == "string" and path ~= "" then
        SetTexture(tex, path)
        SetTexCoord(tex, l or 0, r or 1, t or 0, b or 1)
        return
      end
    end
  end
  local style = cfg and cfg.style
  if type(style) == "string" and style ~= "" and style ~= "DEFAULT" and style ~= "BLIZZARD" then
    local resolver = assist and _G.MSUF_GetAssistStatusIconTexture or _G.MSUF_GetLeaderStatusIconTexture
    if type(resolver) == "function" then
      local path, l, r, t, b = resolver(style, status and status.useMidnight == true)
      if type(path) == "string" and path ~= "" then
        SetTexture(tex, path)
        SetTexCoord(tex, l or 0, r or 1, t or 0, b or 1)
        return
      end
    end
  end
  SetTexture(tex, assist and ASSIST_TEXTURE or LEADER_TEXTURE)
  SetTexCoord(tex, 0, 1, 0, 1)
end

local function ApplyRoleTexture(tex, cfg, status, role)
  if cfg and type(cfg.customIcon) == "string" and cfg.customIcon ~= "" then
    SetTexture(tex, cfg.customIcon)
    SetTexCoord(tex, 0, 1, 0, 1)
    return true
  end
  local gf = MSUF and MSUF.GF
  local kind = status and status.kind
  if gf and kind and type(gf.GetRoleTexture) == "function" then
    local path, l, r, t, b = gf.GetRoleTexture(kind, role, cfg and cfg.style)
    if type(path) == "string" and path ~= "" then
      SetTexture(tex, path)
      SetTexCoord(tex, l or 0, r or 1, t or 0, b or 1)
      return true
    end
  end
  local resolver = _G.MSUF_GetRoleStatusIconTexture
  if type(resolver) == "function" then
    local path, l, r, t, b = resolver(cfg and cfg.style, role, status and status.useMidnight == true)
    if type(path) == "string" and path ~= "" then
      SetTexture(tex, path)
      SetTexCoord(tex, l or 0, r or 1, t or 0, b or 1)
      return true
    end
  end
  return false
end

local function EffectiveStatusIconStyle(cfg, status)
  local style = cfg and cfg.style
  if type(style) ~= "string" or style == "" or style == "DEFAULT" then
    style = status and status.iconStyle
  end
  if type(style) ~= "string" or style == "" or style == "DEFAULT" or style == "BLIZZARD" then
    return nil
  end
  return style
end

local function ApplyStatusIconPackTexture(tex, cfg, status, iconType, variant)
  if not tex then return false end
  if cfg and type(cfg.customIcon) == "string" and cfg.customIcon ~= "" then
    SetTexture(tex, cfg.customIcon)
    SetTexCoord(tex, 0, 1, 0, 1)
    return true
  end
  local style = EffectiveStatusIconStyle(cfg, status)
  if not style then return false end
  local resolver = _G.MSUF_GetStatusIconTexture
  if type(resolver) ~= "function" then
    local gf = MSUF and MSUF.GF
    resolver = gf and gf.GetStatusIconTexture
  end
  if type(resolver) ~= "function" then return false end
  local path, l, r, t, b = resolver(style, iconType, variant, status and status.useMidnight == true)
  if type(path) ~= "string" or path == "" then return false end
  SetTexture(tex, path)
  SetTexCoord(tex, l or 0, r or 1, t or 0, b or 1)
  return true
end

local function ApplyStateOrPackIconTexture(tex, kind, cfg, status, variant, playAnimation)
  if kind == "resting" then
    if cfg and cfg.symbol == RESTING_ANIMATED_SYMBOL
      and ApplyRestingFlipbook(tex, playAnimation) then
      return true
    end
    StopRestingFlipbook(tex, true)
  end
  if SymbolPath(cfg and cfg.symbol, status and status.useMidnight == true) then
    ApplyStateIconTexture(tex, kind, cfg, status)
    return true
  end
  if ApplyStatusIconPackTexture(tex, cfg, status, kind, variant or kind) then
    return true
  end
  ApplyStateIconTexture(tex, kind, cfg, status)
  return true
end

local function HideField(frame, field)
  if type(field) == "table" then
    for i = 1, #field do
      HideField(frame, field[i])
    end
    return
  end
  SetShown(frame and frame[field], false)
end

local CONFIGURED_REGION_DEFS = {
  -- key, field, groupField, hide, aliases, texture, text, state, clearSummon, resetTexCoord
  { "raidMarker", "raidTargetIcon", "raidIcon", { "raidIcon", "raidTargetIcon" }, { "raidTargetIcon", "raidMarkerIndicator" }, RAID_MARKER_TEXTURE },
  { "role", "roleIcon" },
  { "leader", "LeaderIndicator", "leaderIcon", { "leaderIcon", "LeaderIndicator" }, { "LeaderIndicator", "leaderIcon" } },
  { "assist", "assistIcon" },
  { "level", "levelText", nil, nil, nil, nil, true },
  { "race", "raceText", nil, nil, nil, nil, true },
  { "classText", "classStatusText", nil, nil, nil, nil, true },
  { "raidGroup", "raidGroupNameText", nil, nil, nil, nil, true },
  { "elite", "eliteIcon" },
  { "statusText", "statusIndicatorText", nil, nil, nil, nil, true },
  { "combat", "combatStateIndicatorIcon", nil, nil, nil, nil, nil, "combat" },
  { "resting", "restingIndicatorIcon", nil, nil, nil, nil, nil, "resting" },
  { "incomingRes", "incomingResIndicatorIcon", "resurrectIcon", { "resurrectIcon", "incomingResIndicatorIcon" }, { "incomingResIndicatorIcon", "IncomingResIndicator" }, nil, nil, "incomingRes" },
  { "pvp", "pvpIndicatorIcon", "pvpIcon", { "pvpIcon", "pvpIndicatorIcon" }, { "pvpIndicatorIcon", "pvpIcon" } },
  { "stance", "stanceIndicatorText", nil, nil, nil, nil, true },
  { "readyCheck", "readyCheckIcon" },
  { "summon", "summonIcon", nil, nil, nil, nil, nil, nil, true },
  { "phase", "phaseIcon", nil, nil, nil, PHASE_TEXTURE, nil, nil, nil, true },
}

local NAME_FONT_STATUS = {
  level = true,
  race = true,
  classText = true,
  raidGroup = true,
  stance = true,
}

local function HideConfiguredRegion(frame, def)
  local hide = def[4]
  if hide then
    for i = 1, #hide do
      HideField(frame, hide[i])
    end
  else
    HideField(frame, def[2])
  end
  if def[9] and frame then
    frame._msufGFSummonActive = false
  end
end

local function ApplyConfiguredRegion(frame, spec, status, def)
  local key, field, groupField, aliases, texture, text, state, resetTexCoord =
    def[1], def[2], def[3], def[5], def[6], def[7], def[8], def[10]
  local cfg = status[key]
  if not (cfg and cfg.enabled) then
    if key == "resting" then StopRestingFlipbook(frame and frame.restingIndicatorIcon) end
    HideConfiguredRegion(frame, def)
    return
  end
  field = status.group and groupField or field
  local region = text and EnsureText(frame, field, cfg.layer) or EnsureTexture(frame, field, cfg.layer)
  if aliases then
    for i = 1, #aliases do
      frame[aliases[i]] = region
    end
  end
  if texture then
    SetTexture(region, texture)
  end
  if resetTexCoord then
    SetTexCoord(region, 0, 1, 0, 1)
  end
  if state then
    ApplyStateOrPackIconTexture(region, state, cfg, status, state)
  end
  local nameRelative = cfg.anchor == "NAMERIGHT" or cfg.anchor == "NAMELEFT"
  LayoutRegion(region, frame, spec, cfg, text, NAME_FONT_STATUS[key] and nameRelative and "name" or nil)
end

local function ApplyConfiguredRegions(frame, spec)
  local status = spec and spec.status
  if not status then
    if frame then
      frame._msufNameRelativeStatus = nil
      local textRuntime = MSUF.UFText
      if textRuntime and textRuntime.EnsureNameAnchorProxy then
        textRuntime.EnsureNameAnchorProxy(frame, spec)
      end
    end
    return
  end
  local nameRelative
  for i = 1, #CONFIGURED_REGION_DEFS do
    local def = CONFIGURED_REGION_DEFS[i]
    local cfg = status[def[1]]
    if cfg and cfg.enabled == true and (cfg.anchor == "NAMERIGHT" or cfg.anchor == "NAMELEFT") then
      nameRelative = true
    end
  end
  if frame then
    frame._msufNameRelativeStatus = nameRelative
    local textRuntime = MSUF.UFText
    if textRuntime and textRuntime.EnsureNameAnchorProxy then
      textRuntime.EnsureNameAnchorProxy(frame, spec)
    end
  end
  for i = 1, #CONFIGURED_REGION_DEFS do
    ApplyConfiguredRegion(frame, spec, status, CONFIGURED_REGION_DEFS[i])
  end
end

local function RefreshNameRelativeAnchors(frame)
  if not (frame and frame._msufNameRelativeStatus == true) then
    return false
  end
  local status = frame.MSUFSpec and frame.MSUFSpec.status
  if not status then
    return false
  end
  local refreshed
  for i = 1, #CONFIGURED_REGION_DEFS do
    local def = CONFIGURED_REGION_DEFS[i]
    local cfg = status[def[1]]
    if cfg and cfg.enabled == true and (cfg.anchor == "NAMERIGHT" or cfg.anchor == "NAMELEFT") then
      local field = status.group and def[3] or def[2]
      local region = field and frame[field]
      if region then
        AnchorRegion(region, frame, cfg)
        refreshed = true
      end
    end
  end
  return refreshed == true
end

local function ApplyDefaultRaidMarkerTexture(tex, index)
  -- 12.x SetRaidTargetIconTexture is texture:SetSpriteSheetCell(): it slices whatever texture is
  -- currently set and moves the real tex coords behind the SetTexCoord dedupe cache. Re-assert the
  -- stock marker sheet first (cached no-op while it is already set, and required after a custom
  -- icon or pack texture was on this region), then drop the coord cache so a later custom/pack
  -- application cannot be dedupe-skipped against coords the sprite-cell call changed underneath.
  SetTexture(tex, RAID_MARKER_TEXTURE)
  SetRaidTargetIconTexture(tex, index)
  tex._msufStatusL, tex._msufStatusR, tex._msufStatusT, tex._msufStatusB = nil, nil, nil, nil
end

local function UpdateRaidMarker(frame, status)
  local cfg = status and status.raidMarker
  local tex = frame.raidTargetIcon
  local unit = frame.MSUFUnitKey
  local unitState = FreshUnitState(frame, unit)
  local exists = UnitExistsRuntime(unit, unitState, frame)
  if not (cfg and cfg.enabled and tex and GetRaidTargetIndex and SetRaidTargetIconTexture and exists) then
    if tex then
      tex._msufRaidMarkerIndex = nil
      SetShown(tex, false)
    end
    return
  end
  -- tex._msufRaidMarkerIndex contract: non-nil only while the region shows the default sheet cell
  -- for that plain index; every other render nils it so the dedupe below can never skip a repaint.
  local index = GetRaidTargetIndex(unit)
  if issecretvalue(index) == true then
    tex._msufRaidMarkerIndex = nil
    -- A custom icon override is one fixed texture for all eight markers, so it renders without
    -- knowing the secret index; only the default sheet needs the C-side sprite-cell helper.
    local custom = cfg.customIcon
    if type(custom) == "string" and custom ~= "" then
      SetTexture(tex, custom)
      SetTexCoord(tex, 0, 1, 0, 1)
    else
      ApplyDefaultRaidMarkerTexture(tex, index)
    end
    SetShown(tex, true)
    return
  end
  if not index then
    tex._msufRaidMarkerIndex = nil
    SetShown(tex, false)
    return
  end
  if ApplyStatusIconPackTexture(tex, cfg, status, "raidMarker", index) then
    tex._msufRaidMarkerIndex = nil
    SetShown(tex, true)
    return
  end
  if status.group then
    tex._msufRaidMarkerIndex = nil
    ApplyDefaultRaidMarkerTexture(tex, index)
  elseif tex._msufRaidMarkerIndex ~= index then
    ApplyDefaultRaidMarkerTexture(tex, index)
    tex._msufRaidMarkerIndex = index
  end
  SetShown(tex, true)
end

local function UpdateLeader(frame, status)
  local cfg = status and status.leader
  local tex = frame.LeaderIndicator
  local unit = frame.MSUFUnitKey
  local unitState = FreshUnitState(frame, unit)
  local exists = UnitExistsRuntime(unit, unitState, frame)
  if not (cfg and cfg.enabled and tex and exists) then
    SetShown(tex, false)
    return
  end
  local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
  local isAssist = UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
  local leader = BoolTrue(isLeader)
  local assist = (not leader) and BoolTrue(isAssist)
  if leader or assist then
    ApplyLeaderTexture(tex, cfg, status, assist)
    SetShown(tex, true)
  else
    SetShown(tex, false)
  end
end

local function UpdateLeaderPair(frame, status)
  local unit = frame and frame.MSUFUnitKey
  local leaderCfg = status and status.leader
  local assistCfg = status and status.assist
  local leaderTex = frame and (frame.leaderIcon or frame.LeaderIndicator)
  local assistTex = frame and frame.assistIcon
  local unitState = FreshUnitState(frame, unit)
  local exists = UnitExistsRuntime(unit, unitState, frame)
  -- Unit-type early-out: only a PLAYER can be group leader/assistant, so a
  -- non-player target (any mob) can never show these. Skip the two group-query
  -- API calls entirely and just ensure the icons are hidden. This guard makes
  -- rapid target-swaps over mobs cheap.
  if exists and UnitIsPlayerRuntime(unit, unitState, frame) == false then
    if leaderTex and leaderTex._msufStatusShown ~= false then SetShown(leaderTex, false); leaderTex._msufStatusShown = false end
    if assistTex and assistTex._msufStatusShown ~= false then SetShown(assistTex, false); assistTex._msufStatusShown = false end
    frame._msufLeaderPairState = 0
    return
  end
  local leaderRaw = exists and UnitIsGroupLeader and UnitIsGroupLeader(unit)
  local leader = BoolTrue(leaderRaw)
  local assistRaw = exists and (not leader) and UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
  local assist = BoolTrue(assistRaw)

  local showLeader = leaderCfg and leaderCfg.enabled and leaderTex and leader
  local showAssist = assistCfg and assistCfg.enabled and assistTex and assist
  local state = (showLeader and 1 or 0) + (showAssist and 2 or 0)
  local serial = frame and (frame._msufStatusIndicatorSerial
    or (frame.MSUFSpec and frame.MSUFSpec._msufGFCompileSerial)
    or 0)
  if frame
    and frame._msufLeaderPairState == state
    and frame._msufLeaderPairSerial == serial
    and (not leaderTex or leaderTex._msufStatusShown == (showLeader and true or false))
    and (not assistTex or assistTex._msufStatusShown == (showAssist and true or false)) then
    return
  end
  if frame then
    frame._msufLeaderPairState = state
    frame._msufLeaderPairSerial = serial
  end

  if showLeader then
    ApplyLeaderTexture(leaderTex, leaderCfg, status, false)
    SetShown(leaderTex, true)
  else
    SetShown(leaderTex, false)
  end

  if showAssist then
    ApplyLeaderTexture(assistTex, assistCfg, status, true)
    SetShown(assistTex, true)
  else
    SetShown(assistTex, false)
  end
end

local function CancelReadyCheckTimer(frame)
  if frame then
    READY_CHECK_TIMERS[frame] = nil
  end
end

local ReadyCheckTimerCallback

local function ArmReadyCheckTimer(when)
  if READY_CHECK_TIMER_AT and READY_CHECK_TIMER_AT <= when then return end
  READY_CHECK_TIMER_AT = when
  local now = GetTime and GetTime() or 0
  local delay = when - now
  C_Timer.After(delay > 0 and delay or 0, ReadyCheckTimerCallback)
end

ReadyCheckTimerCallback = function()
  -- Ready-check icons share one compact timer queue instead of one timer per frame. The
  -- callback compacts sparse slots so raid-size checks do not leave long-lived table holes.
  READY_CHECK_TIMER_AT = nil
  local now = GetTime and GetTime() or 0
  local nextAt
  local out = READY_CHECK_HEAD
  local last = READY_CHECK_TAIL

  for i = READY_CHECK_HEAD, last do
    local frame = READY_CHECK_LIST[i]
    local due = frame and READY_CHECK_TIMERS[frame]
    if not due then
      READY_CHECK_LIST[i] = nil
    elseif now >= due then
      READY_CHECK_TIMERS[frame] = nil
      READY_CHECK_LIST[i] = nil
      SetShown(frame.readyCheckIcon, false)
    else
      if out ~= i then
        READY_CHECK_LIST[out] = frame
        READY_CHECK_LIST[i] = nil
      end
      out = out + 1
      if not nextAt or due < nextAt then
        nextAt = due
      end
    end
  end

  local appendedTail = READY_CHECK_TAIL
  if appendedTail > last then
    for i = last + 1, appendedTail do
      local frame = READY_CHECK_LIST[i]
      local due = frame and READY_CHECK_TIMERS[frame]
      if due then
        if out ~= i then
          READY_CHECK_LIST[out] = frame
          READY_CHECK_LIST[i] = nil
        end
        out = out + 1
        if not nextAt or due < nextAt then
          nextAt = due
        end
      else
        READY_CHECK_LIST[i] = nil
      end
    end
  end

  READY_CHECK_HEAD = 1
  READY_CHECK_TAIL = out - 1
  if READY_CHECK_TAIL <= 0 then
    READY_CHECK_TAIL = 0
  end
  if nextAt then
    ArmReadyCheckTimer(nextAt)
  end
end

local function QueueReadyCheckHide(frame)
  if not frame then return end
  local now = GetTime and GetTime() or 0
  local due = now + 6
  local known = READY_CHECK_TIMERS[frame] ~= nil
  READY_CHECK_TIMERS[frame] = due
  if not known then
    READY_CHECK_TAIL = READY_CHECK_TAIL + 1
    READY_CHECK_LIST[READY_CHECK_TAIL] = frame
  end
  ArmReadyCheckTimer(due)
end

local function UpdatePowerRoleVisibility(frame, status)
  local spec = frame and frame.MSUFSpec
  if not (frame and (frame._msufGFKind or (spec and spec.scope == "group"))) then
    if frame then
      frame._msufGFPowRoleHidden = nil
    end
    return false
  end
  local bar = frame and (frame.power or frame.Power or frame.powerBar or frame.targetPowerBar)
  if not bar then
    return false
  end
  local unit = frame.MSUFUnitKey
  local c = frame._c
  local gf = MSUF and MSUF.GF
  local role = status and status.roleValue
  if not role then
    if gf and type(gf.GetUnitGroupRole) == "function" then
      role = gf.GetUnitGroupRole(unit)
    else
      role = UnitGroupRolesAssigned and unit and UnitGroupRolesAssigned(unit) or "DAMAGER"
    end
  end
  if issecretvalue(role) == true then
    role = nil
  end
  if gf and type(gf.NormalizeGroupRole) == "function" then
    role = gf.NormalizeGroupRole(role)
  elseif role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
    role = "DAMAGER"
  end

  local hidden = false
  if gf and type(gf.GetEffectivePowerHeight) == "function" then
    hidden = gf.GetEffectivePowerHeight(frame._msufGFKind or status and status.kind or "party", unit, role) <= 0
  elseif c then
    hidden = (role == "TANK" and not c.powTank)
      or (role == "HEALER" and not c.powHealer)
      or (role == "DAMAGER" and not c.powDPS) or false
  end

  local prev = frame._msufGFPowRoleHidden
  -- Preserve both sides of the role gate. Using nil for the visible state made
  -- the first visible -> hidden transition look like initialization, so a
  -- reused healer/tank frame could keep its old Power event ownership as DPS.
  frame._msufGFPowRoleHidden = hidden
  if prev ~= nil and prev ~= hidden then
    -- Role-driven power visibility changes alter event ownership and layout.
    -- MarkDirty owns the combat deferral; outside combat it reapplies the exact
    -- frame immediately, while the group runtime coalesces protected changes.
    if gf and type(gf.MarkDirty) == "function" then
      gf.MarkDirty(frame, (gf.DIRTY_GEOMETRY or 0x01) + (gf.DIRTY_LAYOUT or 0x20))
    end
  end
  return hidden
end

local function UpdateRole(frame, status)
  local cfg = status and status.role
  local tex = frame and frame.roleIcon
  local unit = frame and frame.MSUFUnitKey
  local unitState = FreshUnitState(frame, unit)
  local exists = UnitExistsRuntime(unit, unitState, frame)
  local role = UnitGroupRolesAssigned and unit and UnitGroupRolesAssigned(unit) or nil
  if issecretvalue(role) == true then role = nil end
  if role == "NONE" then role = nil end
  if status then status.roleValue = role end
  UpdatePowerRoleVisibility(frame, status)

  if not (cfg and cfg.enabled and tex and exists and role) then
    SetShown(tex, false)
    return
  end
  if (role == "TANK" and cfg.showTank == false)
    or (role == "HEALER" and cfg.showHealer == false)
    or (role == "DAMAGER" and cfg.showDPS == false) then
    SetShown(tex, false)
    return
  end
  if ApplyRoleTexture(tex, cfg, status, role) then
    SetShown(tex, true)
  else
    SetShown(tex, false)
  end
end

local function UpdateReadyCheck(frame, status, event)
  local cfg = status and status.readyCheck
  local tex = frame and frame.readyCheckIcon
  local unit = frame and frame.MSUFUnitKey
  if not (cfg and cfg.enabled and tex and unit) then
    SetShown(tex, false)
    CancelReadyCheckTimer(frame)
    return
  end

  local ready = GetReadyCheckStatus and GetReadyCheckStatus(unit)
  local texture = READY_TEXTURES[ready]
  if texture then
    CancelReadyCheckTimer(frame)
    if not ApplyStatusIconPackTexture(tex, cfg, status, "readyCheck", ready) then
      SetTexture(tex, texture)
      SetTexCoord(tex, 0, 1, 0, 1)
    end
    SetShown(tex, true)
  elseif event == "READY_CHECK_FINISHED" and tex.IsShown and tex:IsShown() then
    -- Blizzard leaves ready-check result icons visible briefly after finish; queue a delayed
    -- hide so MSUF matches that readable window without polling.
    QueueReadyCheckHide(frame)
  else
    SetShown(tex, false)
  end
end

local function UpdateSummon(frame, status)
  local cfg = status and status.summon
  local tex = frame and frame.summonIcon
  local unit = frame and frame.MSUFUnitKey
  if not (cfg and cfg.enabled and tex and unit) then
    SetShown(tex, false)
    if frame then frame._msufGFSummonActive = false end
    return
  end
  local summonStatus
  if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
    summonStatus = C_IncomingSummon.IncomingSummonStatus(unit)
  end
  if issecretvalue(summonStatus) == true then
    -- Summon status can be restricted; an unknown value means hide the icon, not inspect it.
    summonStatus = nil
  end
  local texture = summonStatus and SUMMON_TEXTURES[summonStatus]
  if texture then
    if not ApplyStatusIconPackTexture(tex, cfg, status, "summon", summonStatus) then
      SetTexture(tex, texture)
      SetTexCoord(tex, 0, 1, 0, 1)
    end
    SetShown(tex, true)
    frame._msufGFSummonActive = true
  else
    SetShown(tex, false)
    frame._msufGFSummonActive = false
  end
end

local function UpdatePhase(frame, status)
  local cfg = status and status.phase
  local tex = frame and frame.phaseIcon
  local unit = frame and frame.MSUFUnitKey
  if not (cfg and cfg.enabled and tex and unit) then
    SetShown(tex, false)
    return
  end
  local reason
  local unitState = FreshUnitState(frame, unit)
  local isPlayer = UnitIsPlayerRuntime(unit, unitState, frame)
  if isPlayer == true and UnitPhaseReason then
    reason = UnitPhaseReason(unit)
  end
  if issecretvalue(reason) ~= true and reason then
    if not ApplyStatusIconPackTexture(tex, cfg, status, "phase", reason) then
      SetTexture(tex, PHASE_TEXTURE)
      SetTexCoord(tex, 0, 1, 0, 1)
    end
    SetShown(tex, true)
  else
    SetShown(tex, false)
  end
end

local function IdentityString(value)
  if issecretvalue(value) == true then
    return value, true
  end
  if type(value) == "string" and value ~= "" then
    return value, true
  end
  return "", false
end

local function IdentityDisplayValue(localizedValue, stableValue)
  -- UnitRace/UnitClass localized names can be identity-secret in restricted
  -- instances. Some client builds render those localized secret strings as the
  -- unit name or as blank text. Their stable second returns remain suitable for
  -- direct, secret-safe FontString display; never inspect or index them in Lua.
  if issecretvalue(localizedValue) == true then
    local _, stablePresent = IdentityString(stableValue)
    if stablePresent then return stableValue end
    return localizedValue
  end
  if type(localizedValue) == "string" and localizedValue ~= "" then
    return localizedValue
  end
  return stableValue
end

local function ShowIdentityText(region, value, present)
  if not region then return end
  if present then
    SetText(region, value)
    SetShown(region, true)
  else
    SetShown(region, false)
  end
end

local IDENTITY_TEXT_FIELDS = { "levelText", "raceText", "classStatusText" }

local function UpdateIdentityTexts(frame, status)
  local levelCfg = status and status.level
  local raceCfg = status and status.race
  local classCfg = status and status.classText
  local showLevel = levelCfg and levelCfg.enabled == true and frame.levelText ~= nil
  local showRace = raceCfg and raceCfg.enabled == true and frame.raceText ~= nil
  local showClass = classCfg and classCfg.enabled == true and frame.classStatusText ~= nil

  if not (showLevel or showRace or showClass) then
    HideField(frame, IDENTITY_TEXT_FIELDS)
    return
  end

  local unit = frame.MSUFUnitKey
  local unitState = FreshUnitState(frame, unit)
  if not UnitExistsRuntime(unit, unitState, frame) then
    HideField(frame, IDENTITY_TEXT_FIELDS)
    return
  end

  local levelText, levelPresent = "", false
  if showLevel and UnitLevel then
    local level = SafeNumber(UnitLevel(unit))
    if level then
      levelText, levelPresent = level == -1 and "??" or tostring(level), true
    end
  end

  local raceText, racePresent = "", false
  if showRace and UnitRace then
    local localizedRace, englishRace = UnitRace(unit)
    raceText, racePresent = IdentityString(IdentityDisplayValue(localizedRace, englishRace))
  end

  local classText, classPresent = "", false
  if showClass then
    local localizedClass, classToken = ReadUnitClassCached(frame, unit)
    classText, classPresent = IdentityString(IdentityDisplayValue(localizedClass, classToken))
  end

  if showLevel then ShowIdentityText(frame.levelText, levelText, levelPresent) else SetShown(frame.levelText, false) end
  if showRace then ShowIdentityText(frame.raceText, raceText, racePresent) else SetShown(frame.raceText, false) end
  if showClass then ShowIdentityText(frame.classStatusText, classText, classPresent) else SetShown(frame.classStatusText, false) end
end

local function RaidGroupText(style, subgroup)
  if style == "BRACKET" then
    return "[" .. subgroup .. "]"
  elseif style == "NONE" then
    return tostring(subgroup)
  end
  return "(" .. subgroup .. ")"
end

--- A secure raid header's unit token already encodes the roster index
--- ("raid7" -> 7), so the group-frame case resolves without an API call and
--- without depending on UnitInRaid resolving that token. UnitInRaid stays as
--- the fallback for party tokens and for target/focus unit frames.
local RAID_TOKEN_INDEX = {}
for i = 1, 40 do RAID_TOKEN_INDEX["raid" .. i] = i end

local function UpdateRaidGroup(frame, status)
  local cfg = status and status.raidGroup
  local fs = frame.raidGroupNameText
  local unit = frame.MSUFUnitKey
  local unitState = FreshUnitState(frame, unit)
  local exists = UnitExistsRuntime(unit, unitState, frame)
  if not (cfg and cfg.enabled and fs and GetRaidRosterInfo and exists) then
    SetShown(fs, false)
    return
  end
  local index = RAID_TOKEN_INDEX[unit]
  if not index then
    -- Only a PLAYER can be in the raid roster, so a mob target never needs the
    -- roster lookup at all; this keeps rapid target-swaps over mobs cheap.
    -- Bail only on a positive "not a player": an unknown identity has to fall
    -- through, or a frame whose identity was never resolved silently loses its
    -- number.
    local isPlayer, isPlayerKnown = ReadUnitIsPlayerCached(frame, unit)
    if isPlayerKnown == true and isPlayer ~= true then
      SetShown(fs, false)
      return
    end
    index = UnitInRaid and SafeNumber(UnitInRaid(unit)) or nil
  end
  local subgroup
  if index then
    local _, _, sg = GetRaidRosterInfo(index)
    if type(sg) == "number" and sg > 0 then
      subgroup = sg
    end
  end
  local serial = frame._msufStatusIndicatorSerial
    or (frame.MSUFSpec and frame.MSUFSpec._msufGFCompileSerial)
    or 0
  if frame._msufRaidGroupSubgroup == subgroup
    and frame._msufRaidGroupSerial == serial
    and fs._msufStatusShown == (subgroup ~= nil) then
    return
  end
  frame._msufRaidGroupSubgroup = subgroup
  frame._msufRaidGroupSerial = serial
  if subgroup then
    SetText(fs, RaidGroupText(cfg.style, subgroup))
    SetShown(fs, true)
  else
    SetShown(fs, false)
  end
end

local function EliteAtlas(state)
  -- Mirror Blizzard_NamePlateClassificationFrame exactly: elite/worldboss use
  -- gold, rare elite uses silver, and rare uses the standalone rare star.
  if state == "RARE" then
    return "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star"
  elseif state == "RAREELITE" then
    return "nameplates-icon-elite-silver"
  end
  return "nameplates-icon-elite-gold"
end

local function EliteState(frame, unit, unitState)
  local exists = UnitExistsRuntime(unit, unitState, frame)
  if not (UnitClassification and exists) then
    return nil
  end
  local class = UnitClassification(unit)
  if issecretvalue(class) == true then
    return nil
  end
  if class == "worldboss" then
    return "BOSS"
  elseif class == "rareelite" then
    return "RAREELITE"
  elseif class == "rare" then
    return "RARE"
  elseif class == "elite" then
    return "ELITE"
  end
  if UnitLevel then
    local level = UnitLevel(unit)
    if SafeNumber(level) == -1 then
      return "BOSS"
    end
  end
  return nil
end

local function UpdateElite(frame, status)
  local cfg = status and status.elite
  local tex = frame.eliteIcon
  if not (cfg and cfg.enabled and tex) then
    SetShown(tex, false)
    return
  end
  -- Opposite gate: only NPCs are elite/rare/boss classifications, so a PLAYER
  -- target can never show this. Skip the classification query for players.
  local unit = frame.MSUFUnitKey
  local unitState = FreshUnitState(frame, unit)
  if status.testMode ~= true and UnitIsPlayerRuntime(unit, unitState, frame) == true then
    SetShown(tex, false)
    return
  end
  local state = status.testMode and "BOSS" or EliteState(frame, unit, unitState)
  if state then
    if ApplyStatusIconPackTexture(tex, cfg, status, "elite", state) then
      SetShown(tex, true)
      return
    elseif tex.SetAtlas then
      SetAtlas(tex, EliteAtlas(state))
    else
      SetTexture(tex, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
      SetTexCoord(tex, 0, 1, 0, 1)
    end
    SetShown(tex, true)
  else
    SetShown(tex, false)
  end
end

local function SeedHealthDeadOverride(seedHP)
  if issecretvalue(seedHP) == true or type(seedHP) ~= "number" then
    return nil
  end
  return seedHP <= 0
end

local function StatusText(frame, cfg, unitState, seedHP)
  local unit = frame.MSUFUnitKey
  local healthDead = SeedHealthDeadOverride(seedHP)
  if cfg and cfg.showDead then
    local connected, connectedKnown = ReadConnectedCached(frame, unit, unitState)
    if connectedKnown == true and connected == false then
      return "OFFLINE", "dead"
    end
  end
  if healthDead ~= false and cfg and cfg.showGhost and UnitIsGhost then
    local ghost = UnitIsGhost(unit)
    if BoolTrue(ghost) then
      return "GHOST", "ghost"
    end
  end
  if cfg and cfg.showDead then
    local dead, deadKnown
    if healthDead ~= nil then
      dead, deadKnown = healthDead, true
    else
      dead, deadKnown = ReadDeadCached(frame, unit, unitState)
    end
    if deadKnown == true and dead == true then
      return "DEAD", "dead"
    end
  end
  if cfg and cfg.showAFK and UnitIsAFK then
    local afk = UnitIsAFK(unit)
    if BoolTrue(afk) then
      return "AFK", "afk"
    end
  end
  if cfg and cfg.showDND and UnitIsDND then
    local dnd = UnitIsDND(unit)
    if BoolTrue(dnd) then
      return "DND", "dnd"
    end
  end
  return nil
end

local function RefreshHealthAfterGoneStatus(frame, oldValue)
  if oldValue ~= "DEAD" and oldValue ~= "GHOST" and oldValue ~= "OFFLINE" then
    return
  end
  -- A group-state snapshot has already written authoritative detailed health.
  -- Do not immediately replace it with a second direct-health read while the
  -- client is still committing an AI/secure-header transition.
  if frame._msufGroupStateRefresh == true or frame._msufHealthStateNotify == true then
    return
  end
  if frame._msufStatusTextHealthRefresh == true then
    return
  end
  local active = frame._msufActiveElements
  if not (active and active.Health == true) then
    return
  end
  local health = UF.elements and UF.elements.Health
  local update = health and health.Update
  local unit = frame.MSUFUnitKey
  if not (type(update) == "function" and type(unit) == "string" and unit ~= "" and issecretvalue(unit) ~= true) then
    return
  end
  local refreshed = false
  local hadDeadBg = frame._msufGFDeadBgState == true
  local gone = frame._msufUpdateGroupVisualsGoneState
  if type(gone) == "function" then
    gone(frame, "MSUF_STATUS_TEXT_CLEAR", unit)
    refreshed = hadDeadBg and frame._msufGFDeadBgState ~= true
  end
  if refreshed == true then
    return
  end
  frame._msufStatusTextHealthRefresh = true
  update(frame, "MSUF_STATUS_TEXT_CLEAR", unit)
  frame._msufStatusTextHealthRefresh = nil
end

local function StatusTextIsGone(value)
  return value == "DEAD" or value == "GHOST" or value == "OFFLINE"
end

local function HideAFKTimerText(frame)
  if not frame then return end
  local fs = frame.statusAFKTimerText
  if fs then
    SetText(fs, "")
    SetShown(fs, false)
  end
  frame._msufAFKTimerLayout = nil
  local afkTimer = MSUF.UFAFKTimer
  if afkTimer and afkTimer.Detach then afkTimer.Detach(frame) end
end

--- Companion region to the AFK status text: shows how long the unit has been
--- AFK. Data comes from the shared GUID ledger (MSUF.UFAFKTimer), which is
--- strictly out-of-combat; ResolveText returns nil in combat or when the
--- AFK-on edge was never observed, so this hides instead of guessing.
local function UpdateAFKTimerText(frame, status, cfg, state)
  local tcfg = cfg and cfg.afkTimer
  if not (tcfg and tcfg.enabled == true and state == "afk") then
    HideAFKTimerText(frame)
    return
  end
  local afkTimer = MSUF.UFAFKTimer
  if not afkTimer then return end
  local text
  if status.testMode == true then
    text = afkTimer.SampleText()
  else
    text = afkTimer.ResolveText(frame.MSUFUnitKey)
  end
  if type(text) ~= "string" or text == "" then
    HideAFKTimerText(frame)
    return
  end
  local fs = EnsureText(frame, "statusAFKTimerText", tcfg.layer)
  if not fs then return end
  if frame._msufAFKTimerLayout ~= tcfg then
    frame._msufAFKTimerLayout = tcfg
    AdoptRegion(frame, fs, tcfg.layer)
    LayoutRegion(fs, frame, frame.MSUFSpec, tcfg, true)
  end
  SetText(fs, text)
  SetShown(fs, true)
  if status.testMode ~= true then
    if afkTimer.Attach then afkTimer.Attach(frame) end
  elseif afkTimer.Detach then
    afkTimer.Detach(frame)
  end
end

local function ClearStatusText(frame, fs)
  HideAFKTimerText(frame)
  if frame._msufStatusTextValue == nil
    and frame._msufStatusTextLayout == nil
    and fs and fs._msufStatusShown == false then
    return
  end
  local oldValue = frame._msufStatusTextValue
  frame._msufStatusTextValue = nil
  frame._msufStatusTextLayout = nil
  if fs then
    SetText(fs, "")
    SetShown(fs, false)
  end
  RefreshHealthAfterGoneStatus(frame, oldValue)
end

local function UpdateStatusText(frame, status, event, seedHP)
  local cfg = status and status.statusText
  local fs = frame.statusIndicatorText
  local unit = frame.MSUFUnitKey
  if not (cfg and cfg.enabled and fs) then
    ClearStatusText(frame, fs)
    return
  end
  local unitState = FreshUnitState(frame, unit)
  if status.testMode ~= true
    and event == "UNIT_HEALTH"
    and frame._msufStatusTextValue == nil
    and fs._msufStatusShown == false
    and (cfg.showDead == true or cfg.showGhost == true) then
    local healthDead = SeedHealthDeadOverride(seedHP)
    local deadOrGhost = healthDead == true or ReadDeadCached(frame, unit, unitState)
    if deadOrGhost ~= true then
      return
    end
  elseif status.testMode ~= true
    and event == "UNIT_HEALTH"
    and frame._msufStatusTextValue == nil
    and cfg.showDead ~= true
    and cfg.showGhost ~= true then
    return
  end
  if not UnitExistsRuntime(unit, unitState, frame) then
    ClearStatusText(frame, fs)
    return
  end
  local text, state
  if status.testMode then
    if cfg.showDead then
      text, state = "DEAD", "dead"
    elseif cfg.showGhost then
      text, state = "GHOST", "ghost"
    elseif cfg.showAFK then
      text, state = "AFK", "afk"
    elseif cfg.showDND then
      text, state = "DND", "dnd"
    end
  end
  if not text then
    text, state = StatusText(frame, cfg, unitState, seedHP)
  end
  if text then
    local layout = cfg
    if state == "ghost" and cfg.ghost then
      layout = cfg.ghost
    elseif state == "afk" and cfg.afk then
      layout = cfg.afk
    elseif state == "dnd" and cfg.dnd then
      layout = cfg.dnd
    elseif cfg.dead then
      layout = cfg.dead
    end
    if layout and layout.enabled == false then
      ClearStatusText(frame, fs)
      return
    end
    -- Before the unchanged early-out: the ledger ticker re-enters this
    -- function with an unchanged main text and only the duration moves.
    UpdateAFKTimerText(frame, status, cfg, state)
    if frame._msufStatusTextValue == text
      and frame._msufStatusTextLayout == layout
      and fs._msufStatusShown == true then
      return
    end
    local oldValue = frame._msufStatusTextValue
    frame._msufStatusTextValue = text
    frame._msufStatusTextLayout = layout
    if layout ~= cfg then
      AdoptRegion(frame, fs, layout.layer)
    end
    LayoutRegion(fs, frame, frame.MSUFSpec, layout, true)
    SetText(fs, text)
    SetShown(fs, true)
    if StatusTextIsGone(oldValue) and not StatusTextIsGone(text) then
      RefreshHealthAfterGoneStatus(frame, oldValue)
    end
  else
    ClearStatusText(frame, fs)
  end
end

local function UpdateCombat(frame, status)
  local cfg = status and status.combat
  local tex = frame.combatStateIndicatorIcon
  local unit = frame.MSUFUnitKey
  local unitState = FreshUnitState(frame, unit)
  local exists = UnitExistsRuntime(unit, unitState, frame)
  if not (cfg and cfg.enabled and tex and exists) then
    SetShown(tex, false)
    return
  end
  local active = status.testMode
  if not active and UnitAffectingCombat then
    local activeRaw = UnitAffectingCombat(unit)
    active = BoolTrue(activeRaw)
  end
  if active == true then
    ApplyStateOrPackIconTexture(tex, "combat", cfg, status, "combat")
    SetShown(tex, true)
  else
    SetShown(tex, false)
  end
end

local function UpdateResting(frame, status)
  local cfg = status and status.resting
  local tex = frame.restingIndicatorIcon
  if not (cfg and cfg.enabled and tex) then
    StopRestingFlipbook(tex)
    SetShown(tex, false)
    return
  end
  local active = status.testMode
  if not active and frame.MSUFUnitKey == "player" and IsResting then
    local activeRaw = IsResting()
    active = BoolTrue(activeRaw)
  end
  if active == true then
    SetShown(tex, true)
    ApplyStateOrPackIconTexture(tex, "resting", cfg, status, "resting", true)
  else
    StopRestingFlipbook(tex)
    SetShown(tex, false)
  end
end

local function UpdateIncomingRes(frame, status)
  local cfg = status and status.incomingRes
  local tex = frame.incomingResIndicatorIcon
  local unit = frame.MSUFUnitKey
  local unitState = FreshUnitState(frame, unit)
  local exists = UnitExistsRuntime(unit, unitState, frame)
  if not (cfg and cfg.enabled and tex and exists) then
    SetShown(tex, false)
    return
  end
  if frame._msufGFSummonActive then
    SetShown(tex, false)
    return
  end
  -- Only players get resurrected; a mob target never has incoming res. Skip the
  -- API query for non-players.
  if status.testMode ~= true and UnitIsPlayerRuntime(unit, unitState, frame) == false then
    SetShown(tex, false)
    return
  end
  local active = status.testMode
  if not active and UnitHasIncomingResurrection then
    local activeRaw = UnitHasIncomingResurrection(unit)
    active = BoolTrue(activeRaw)
  end
  if active == true then
    ApplyStateOrPackIconTexture(tex, "incomingRes", cfg, status, "resurrect")
    SetShown(tex, true)
  else
    SetShown(tex, false)
  end
end

local function PVPVariantForAtlas(atlas)
  if atlas == PVP_HORDE_ATLAS then return "Horde" end
  if atlas == PVP_FFA_ATLAS then return "FFA" end
  return "Alliance"
end

local function UpdatePVP(frame, status)
  local cfg = status and status.pvp
  local tex = frame and frame.pvpIndicatorIcon
  local unit = frame and frame.MSUFUnitKey
  if not (cfg and cfg.enabled and tex and unit) then
    SetShown(tex, false)
    return
  end
  local unitState = FreshUnitState(frame, unit)
  local atlas = status.testMode and ResolvePVPTestAtlas(unit) or ResolvePVPAtlas(frame, unit, unitState)
  if atlas and ApplyStatusIconPackTexture(tex, cfg, status, "pvp", PVPVariantForAtlas(atlas)) then
    SetShown(tex, true)
  elseif ApplyPVPTexture(tex, atlas) then
    SetShown(tex, true)
  else
    SetShown(tex, false)
  end
end

--- Player stance / form / aura text from the native stance bar. Data comes
--- from MSUF.UFStance (spellID -> name cache, immutable per session); the
--- reads are the player's own action-bar state, so they stay valid in combat
--- and the text updates live while stance-dancing. Region creation, font,
--- color and anchoring are owned by ApplyConfiguredRegions - this only moves
--- the text. Lives on Status rather than as a local: the file's main chunk
--- is at Lua's 200-local ceiling.
function Status.UpdateStanceText(frame, status)
  local cfg = status and status.stance
  local fs = frame.stanceIndicatorText
  if not (cfg and cfg.enabled and fs) then
    SetShown(fs, false)
    return
  end
  local stance = MSUF.UFStance
  local text
  if status.testMode == true then
    text = stance and stance.SampleText and stance.SampleText() or nil
  else
    text = stance and stance.Resolve and stance.Resolve() or nil
  end
  if type(text) ~= "string" or text == "" then
    frame._msufStanceTextValue = nil
    SetShown(fs, false)
    return
  end
  if frame._msufStanceTextValue == text and fs._msufStatusShown == true then
    return
  end
  frame._msufStanceTextValue = text
  SetText(fs, text)
  SetShown(fs, true)
end

function Status.IsEnabled(frame, spec)
  return spec and spec.status and spec.status.enabled == true
end

function Status.GetEvents()
  return EMPTY_EVENTS
end

function Status.GetUnitlessEvents()
  return EMPTY_EVENTS
end

function Status.Apply(frame, spec)
  if frame then
    frame._msufStatusTextValue = nil
    frame._msufStatusTextLayout = nil
    frame._msufAFKTimerLayout = nil
  end
  ApplyConfiguredRegions(frame, spec)
  -- ApplyConfiguredRegions lays the status text out with its base table, but a
  -- visible AFK/DND/DEAD/GHOST text owns a per-state layout. Parent-only
  -- refreshes (font runtime, PvP context, group reseeds) have no child update
  -- following them, so re-resolve the state here or the shown text keeps the
  -- base position/size until the next flags event.
  local status = spec and spec.status
  if frame and status then
    UpdateStatusText(frame, status, "MSUF_ELEMENT_APPLY")
  end
end

function Status.Disable(frame)
  StopRestingFlipbook(frame and frame.restingIndicatorIcon)
  HideAFKTimerText(frame)
  for i = 1, #CONFIGURED_REGION_DEFS do
    HideConfiguredRegion(frame, CONFIGURED_REGION_DEFS[i])
  end
  frame._msufStatusTextValue = nil
  frame._msufStatusTextLayout = nil
  frame._msufNameRelativeStatus = nil
  CancelReadyCheckTimer(frame)
end

local RAID_MARKER_EVENTS = { "RAID_TARGET_UPDATE" }
local LEADER_EVENTS = { "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }
local LEVEL_EVENTS = { "UNIT_LEVEL" }
local LEVEL_UNITLESS_EVENTS = { "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED" }
local IDENTITY_NAME_EVENTS = { "UNIT_NAME_UPDATE" }
local IDENTITY_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_LEVEL" }
local RAID_GROUP_EVENTS = { "GROUP_ROSTER_UPDATE" }
local ELITE_EVENTS = { "UNIT_CLASSIFICATION_CHANGED", "UNIT_LEVEL" }
local STATUS_TEXT_EVENTS = { "UNIT_CONNECTION", "UNIT_FLAGS" }
local STATUS_TEXT_CONNECTION_EVENTS = { "UNIT_CONNECTION" }
local STATUS_TEXT_FLAGS_EVENTS = { "UNIT_FLAGS" }
-- AFK/DND edges on observed units arrive as PLAYER_FLAGS_CHANGED (a unit event
-- despite the prefix); UNIT_FLAGS never fires for another unit's AFK toggle.
local STATUS_TEXT_AFK_EVENTS = { "UNIT_CONNECTION", "UNIT_FLAGS", "PLAYER_FLAGS_CHANGED" }
local STATUS_TEXT_FLAGS_AFK_EVENTS = { "UNIT_FLAGS", "PLAYER_FLAGS_CHANGED" }
local STATUS_TEXT_UNITLESS_EVENTS = { "PLAYER_FLAGS_CHANGED" }
local STATUS_TEXT_LIFECYCLE_EVENTS = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
local STATUS_TEXT_PLAYER_UNITLESS_EVENTS = { "PLAYER_FLAGS_CHANGED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
local COMBAT_EVENTS = { "UNIT_FLAGS" }
local COMBAT_PLAYER_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local RESTING_PLAYER_EVENTS = { "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" }
local INCOMING_RES_EVENTS = { "INCOMING_RESURRECT_CHANGED" }
local PVP_EVENTS = { "UNIT_FACTION" }

local function StatusEnabled(spec, key)
  local status = spec and spec.status
  if key == "identityText" then
    return status and status.enabled == true
      and ((status.level and status.level.enabled == true)
        or (status.race and status.race.enabled == true)
        or (status.classText and status.classText.enabled == true))
  end
  local cfg = status and status[key]
  if key == "leader" and not (cfg and cfg.enabled == true) then
    local assist = status and status.assist
    return status and status.enabled == true and assist and assist.enabled == true
  end
  return status and status.enabled == true and cfg and cfg.enabled == true
end

local function IdentityTextEvents(spec)
  if not StatusEnabled(spec, "identityText") then return EMPTY_EVENTS end
  local status = spec.status
  local needsLevel = status.level and status.level.enabled == true
  local needsName = (status.race and status.race.enabled == true)
    or (status.classText and status.classText.enabled == true)
  if needsLevel and needsName then return IDENTITY_EVENTS end
  if needsName then return IDENTITY_NAME_EVENTS end
  return needsLevel and LEVEL_EVENTS or EMPTY_EVENTS
end

local function IdentityTextUnitlessEvents(spec, frame)
  if not (frame and frame.MSUFUnitKey == "player" and StatusEnabled(spec, "identityText")) then
    return EMPTY_EVENTS
  end
  local status = spec.status
  return (status.level and status.level.enabled == true) and LEVEL_UNITLESS_EVENTS or EMPTY_EVENTS
end

local function StatusTextEvents(spec, frame)
  if not StatusEnabled(spec, "statusText") then
    return EMPTY_EVENTS
  end
  local cfg = spec.status.statusText
  local player = frame and frame.MSUFUnitKey == "player"
  local needsConnection = cfg.showDead == true and player ~= true
  local needsFlags = cfg.showDead == true or cfg.showGhost == true or cfg.showAFK == true or cfg.showDND == true
  -- The player frame already receives PLAYER_FLAGS_CHANGED through its
  -- unitless route below; every other frame needs it unit-filtered.
  local needsPlayerFlags = player ~= true and (cfg.showAFK == true or cfg.showDND == true)
  if needsConnection then
    if needsPlayerFlags then
      return STATUS_TEXT_AFK_EVENTS
    end
    return needsFlags and STATUS_TEXT_EVENTS or STATUS_TEXT_CONNECTION_EVENTS
  end
  if needsPlayerFlags then
    return STATUS_TEXT_FLAGS_AFK_EVENTS
  end
  return needsFlags and STATUS_TEXT_FLAGS_EVENTS or EMPTY_EVENTS
end

local function StatusTextUnitlessEvents(spec, frame)
  if not StatusEnabled(spec, "statusText") then
    return EMPTY_EVENTS
  end
  if not (frame and frame.MSUFUnitKey == "player") then
    return EMPTY_EVENTS
  end
  local cfg = spec.status.statusText
  local needsFlags = cfg.showAFK == true or cfg.showDND == true
  local needsLifecycle = cfg.showDead == true or cfg.showGhost == true
  if needsFlags and needsLifecycle then
    return STATUS_TEXT_PLAYER_UNITLESS_EVENTS
  elseif needsFlags then
    return STATUS_TEXT_UNITLESS_EVENTS
  elseif needsLifecycle then
    return STATUS_TEXT_LIFECYCLE_EVENTS
  end
  return EMPTY_EVENTS
end

local function PVPEvents(spec)
  return StatusEnabled(spec, "pvp") and PVP_EVENTS or EMPTY_EVENTS
end

local function CombatEvents(spec, frame)
  if frame and frame.MSUFUnitKey == "player" then
    return EMPTY_EVENTS
  end
  return StatusEnabled(spec, "combat") and COMBAT_EVENTS or EMPTY_EVENTS
end

local Runtime = {
  EMPTY_EVENTS = EMPTY_EVENTS,
  RAID_MARKER_EVENTS = RAID_MARKER_EVENTS,
  LEADER_EVENTS = LEADER_EVENTS,
  LEVEL_EVENTS = LEVEL_EVENTS,
  LEVEL_UNITLESS_EVENTS = LEVEL_UNITLESS_EVENTS,
  IDENTITY_NAME_EVENTS = IDENTITY_NAME_EVENTS,
  IDENTITY_EVENTS = IDENTITY_EVENTS,
  IdentityTextEvents = IdentityTextEvents,
  IdentityTextUnitlessEvents = IdentityTextUnitlessEvents,
  RAID_GROUP_EVENTS = RAID_GROUP_EVENTS,
  ELITE_EVENTS = ELITE_EVENTS,
  STATUS_TEXT_EVENTS = STATUS_TEXT_EVENTS,
  STATUS_TEXT_UNITLESS_EVENTS = STATUS_TEXT_UNITLESS_EVENTS,
  StatusTextEvents = StatusTextEvents,
  StatusTextUnitlessEvents = StatusTextUnitlessEvents,
  CombatEvents = CombatEvents,
  COMBAT_EVENTS = COMBAT_EVENTS,
  COMBAT_PLAYER_EVENTS = COMBAT_PLAYER_EVENTS,
  RESTING_PLAYER_EVENTS = RESTING_PLAYER_EVENTS,
  INCOMING_RES_EVENTS = INCOMING_RES_EVENTS,
  PVP_EVENTS = PVP_EVENTS,
  StatusEnabled = StatusEnabled,
  HideField = HideField,
  ApplyConfiguredRegions = ApplyConfiguredRegions,
  RefreshNameRelativeAnchors = RefreshNameRelativeAnchors,
  CancelReadyCheckTimer = CancelReadyCheckTimer,
  UpdateRaidMarker = UpdateRaidMarker,
  UpdateLeader = UpdateLeader,
  UpdateLeaderPair = UpdateLeaderPair,
  UpdatePowerRoleVisibility = UpdatePowerRoleVisibility,
  UpdateRole = UpdateRole,
  UpdateReadyCheck = UpdateReadyCheck,
  UpdateSummon = UpdateSummon,
  UpdatePhase = UpdatePhase,
  UpdateLevel = UpdateIdentityTexts,
  UpdateIdentityTexts = UpdateIdentityTexts,
  UpdateRaidGroup = UpdateRaidGroup,
  RaidGroupText = RaidGroupText,
  UpdateElite = UpdateElite,
  UpdateStatusText = UpdateStatusText,
  UpdateCombat = UpdateCombat,
  UpdateResting = UpdateResting,
  UpdateIncomingRes = UpdateIncomingRes,
  UpdatePVP = UpdatePVP,
}
MSUF.UFStatusRuntime = Runtime

local StatusStructure = {}
StatusStructure.GetEvents = Status.GetEvents
StatusStructure.GetUnitlessEvents = Status.GetUnitlessEvents
StatusStructure.Create = Status.Create
StatusStructure.Apply = Status.Apply
StatusStructure.Disable = Status.Disable
StatusStructure.IsEnabled = Status.IsEnabled

UF.RegisterElement("StatusIndicators", StatusStructure)

local function RegisterStatusIndicator(def)
  -- Regions are created by StatusIndicators immediately before these child
  -- elements are applied. Seed each child once on every spec apply; afterwards
  -- its narrow event route and the unit-identity path keep it current.
  local element = { UpdateOnApply = true }
  local name, key, events, unitlessEvents = def[1], def[2], def[3], def[4]
  local update, hide = def[5], def[6]
  local noGroup, playerOnly, getEvents = def[7], def[8], def[9]
  local getUnitlessEvents, playerUnitlessEvents, updateWithEvent = def[10], def[11], def[12]

  function element.IsEnabled(frame, spec)
    if playerOnly == true and not (frame and frame.MSUFUnitKey == "player") then
      return false
    end
    if noGroup == true and spec and spec.status and spec.status.group == true then
      return false
    end
    return StatusEnabled(spec, key)
  end

  if getEvents then
    function element.GetEvents(frame, spec)
      return getEvents(spec, frame)
    end
  elseif events then
    function element.GetEvents()
      return events
    end
  end

  if getUnitlessEvents then
    function element.GetUnitlessEvents(frame, spec)
      return getUnitlessEvents(spec, frame)
    end
  elseif playerUnitlessEvents then
    function element.GetUnitlessEvents(frame)
      return frame and frame.MSUFUnitKey == "player" and playerUnitlessEvents or EMPTY_EVENTS
    end
  elseif unitlessEvents then
    function element.GetUnitlessEvents()
      return unitlessEvents
    end
  end

  if updateWithEvent == true then
    function element.Update(frame, event, _unit, seedHP)
      update(frame, frame._msufStatusIndicatorStatus, event, seedHP)
    end
  else
    function element.Update(frame)
      update(frame, frame._msufStatusIndicatorStatus)
    end
  end

  function element.Apply(frame, spec)
    if frame then
      frame._msufStatusIndicatorStatus = spec and spec.status or nil
      frame._msufStatusIndicatorSerial = spec and spec._msufGFCompileSerial or 0
    end
  end

  function element.Disable(frame)
    if key == "resting" then StopRestingFlipbook(frame and frame.restingIndicatorIcon) end
    HideField(frame, hide)
  end

  UF.RegisterElement(name, element)
end

local STATUS_INDICATOR_DEFS = {
  { "RaidMarkerIndicator", "raidMarker", nil, RAID_MARKER_EVENTS, UpdateRaidMarker, "raidTargetIcon", true },
  { "LeaderIndicator", "leader", nil, LEADER_EVENTS, UpdateLeaderPair, { "LeaderIndicator", "leaderIcon", "assistIcon" }, true },
  { "LevelIndicator", "identityText", nil, nil, UpdateIdentityTexts, { "levelText", "raceText", "classStatusText" }, nil, nil, IdentityTextEvents, IdentityTextUnitlessEvents },
  { "RaidGroupIndicator", "raidGroup", nil, RAID_GROUP_EVENTS, UpdateRaidGroup, "raidGroupNameText", true },
  { "EliteIndicator", "elite", ELITE_EVENTS, nil, UpdateElite, "eliteIcon" },
  { "StatusTextIndicator", "statusText", nil, nil, UpdateStatusText, "statusIndicatorText", true, nil, StatusTextEvents, StatusTextUnitlessEvents, nil, true },
  { "CombatIndicator", "combat", nil, nil, UpdateCombat, "combatStateIndicatorIcon", nil, nil, CombatEvents, nil, COMBAT_PLAYER_EVENTS },
  { "RestingIndicator", "resting", nil, RESTING_PLAYER_EVENTS, UpdateResting, "restingIndicatorIcon", nil, true },
  { "IncomingResIndicator", "incomingRes", INCOMING_RES_EVENTS, nil, UpdateIncomingRes, "incomingResIndicatorIcon", true },
  { "PVPIndicator", "pvp", nil, nil, UpdatePVP, "pvpIndicatorIcon", true, nil, PVPEvents },
  -- Stance text events fire only on user action or a stance-bar rebuild
  -- (talents, level-up, loading screen). Never add
  -- UPDATE_SHAPESHIFT_COOLDOWN - it fires with practically every GCD and
  -- would turn this indicator into a hot path.
  { "StanceIndicator", "stance", nil,
    { "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_ENTERING_WORLD" },
    Status.UpdateStanceText, "stanceIndicatorText", true, true },
}

for i = 1, #STATUS_INDICATOR_DEFS do
  RegisterStatusIndicator(STATUS_INDICATOR_DEFS[i])
end

local function RefreshStatus(unit, reason)
  if UF.RefreshElements then
    return UF.RefreshElements(unit, STATUS_REFRESH, reason or "MSUF_STATUS")
  end
  return false
end

UF.RefreshStatusIndicators = RefreshStatus
local STATUS_REFRESH_ALIASES = {
  "MSUF_RefreshStatusIndicators",
  "MSUF_RequestStatusIconsRefreshForCurrent",
  "MSUF_RequestStatusTextRefresh",
  "MSUF_RequestStatusCombatIndicatorRefresh",
  "MSUF_RequestStatusRestingIndicatorRefresh",
  "MSUF_RequestStatusIncomingResIndicatorRefresh",
  "MSUF_RequestStatusPvpIndicatorRefresh",
  "MSUF_RefreshLeaderIconFrames",
  "MSUF_RefreshRaidMarkerFrames",
  "MSUF_RefreshLevelIndicatorFrames",
  "MSUF_RefreshIdentityTextFrames",
  "MSUF_RefreshRaidGroupNameFrames",
  "MSUF_RefreshEliteIconFrames",
}
for i = 1, #STATUS_REFRESH_ALIASES do
  _G[STATUS_REFRESH_ALIASES[i]] = function(unit, reason)
    return RefreshStatus(unit, reason or "MSUF_STATUS")
  end
end
