local addonName, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "MSUF_UF_Elements_Status.lua")

local UF = MSUF.UF

-- Bind mandatory factories once; report both the consumer and received shape.
local function RequireFactory(key)
  local factories = MSUF.UFModuleFactories
  assert(type(factories) == "table", "Elements/MSUF_UF_Elements_Status.lua: required UF factory registry for " .. key)
  local factory = factories[key]
  local kind = type(factory)
  assert(kind == "function", "Elements/MSUF_UF_Elements_Status.lua: required UF provider " .. key .. " (expected function, got " .. kind .. ")")
  return factory
end
if not UF then return end
local Layers = UF.Layers or {}
local Shared = UF.Shared

-- Unitframe status indicator element.
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

local GetBossIndexFromToken = MSUF.Require("GetBossIndexFromToken", "UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua", MSUF.Public)

local issecretvalue = issecretvalue
local ClearFontStringApplyCaches = MSUF.Require("MSUF_ClearFontStringApplyCaches", "UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua")
local MarkFontApplyFailed = MSUF.Require("MSUF_MarkFontApplyFailed", "UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua")
-- The icon-pack resolvers (GroupFrames DB textures, loaded after the elements) are
-- published only through ExportPublic: the Public mirror read is live and call-free.
local PublicAPI = MSUF.Public
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
local ApplyTexture = Apply.Texture
local ApplyText = Apply.Text

local EMPTY_EVENTS = {}
-- Texture paths and atlas names of the indicators: one table of constants.
local Media = {
  WHITE = "Interface\\Buttons\\WHITE8x8",
  RAID_MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons",
  LEADER_TEXTURE = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
  ASSIST_TEXTURE = "Interface\\GroupFrame\\UI-Group-AssistantIcon",
  LEADER_ATLAS = "UI-HUD-UnitFrame-Player-Group-LeaderIcon",
  ASSIST_ATLAS = "UI-HUD-UnitFrame-Player-Group-GuideIcon",
  COMBAT_ATLAS = "UI-HUD-UnitFrame-Player-CombatIcon",
  READY_TEXTURES = {
    ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
  },
  READY_REZ_TEXTURE = "Interface\\RaidFrame\\Raid-Icon-Rez",
  PHASE_TEXTURE = "Interface\\TargetingFrame\\UI-PhasingIcon",
  STATE_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon",
  RESTING_ANIMATED_SYMBOL = "rested_blizzard_animated",
  RESTING_FLIPBOOK_ATLAS = "UI-HUD-UnitFrame-Player-Rest-Flipbook",
  PVP_FFA_ATLAS = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
  PVP_ALLIANCE_ATLAS = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon",
  PVP_HORDE_ATLAS = "UI-HUD-UnitFrame-Player-PVP-HordeIcon",
  SYMBOL_BASE = "Interface\\AddOns\\" .. (addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Symbols\\",
}
Media.PVP_ATLAS_BY_FACTION = { Horde = Media.PVP_HORDE_ATLAS, Alliance = Media.PVP_ALLIANCE_ATLAS }
Media.PVP_TEXTURE_BY_ATLAS = {
  [Media.PVP_HORDE_ATLAS] = "Interface\\TargetingFrame\\UI-PVP-Horde",
  [Media.PVP_ALLIANCE_ATLAS] = "Interface\\TargetingFrame\\UI-PVP-Alliance",
}
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
  "BossNumberIndicator",
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
-- Ready-check hide queue: frames by hide time, one shared timer.
local ReadyCheckQueue = { timers = setmetatable({}, { __mode = "k" }), list = {}, head = 1, tail = 0, timerAt = nil }

local Status = {}
--- Exported runtime (MSUF.UFStatusRuntime). The per-indicator updaters, their
--- event lists and the event resolvers live on it directly instead of as file
--- locals: group status and the indicator registrations below read them from
--- here.
local Runtime = {}

local function SetFont(region, spec, size, role)
  if not region or not region.SetFont then
    return true
  end
  local flags = spec and spec.fontFlags or "OUTLINE"
  size = Shared.ClampFontSize(size, 14)
  local font = spec and spec.font
  local resolveRoleFont = MSUF.UFText and MSUF.UFText.ResolveRoleFont
  if role and type(resolveRoleFont) == "function" then
    font = resolveRoleFont(font, role, size)
  end
  local fontEpoch = tonumber(MSUF_FontApplyEpoch) or 0
  local fontReady = region._msufStatusFontPending ~= true
  if font and (region._msufStatusFontAttemptEpoch ~= fontEpoch
      or region._msufStatusFont ~= font
      or region._msufStatusFontSize ~= size
      or region._msufStatusFontFlags ~= flags)
  then
    if Shared.ApplyFontChecked(region, font, size, flags, 14) then
      region._msufStatusFont, region._msufStatusFontSize, region._msufStatusFontFlags = font, size, flags
      region._msufStatusFontEpoch = fontEpoch
      region._msufStatusFontAttemptEpoch = fontEpoch
      region._msufStatusFontPending = nil
      fontReady = true
    else
      ClearFontStringApplyCaches(region)
      region._msufStatusFont, region._msufStatusFontSize, region._msufStatusFontFlags = font, size, flags
      region._msufStatusFontEpoch = nil
      region._msufStatusFontAttemptEpoch = fontEpoch
      region._msufStatusFontPending = true
      MarkFontApplyFailed()
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

-- Atlas data cannot change while the client runs, and GetAtlasInfo builds a
-- new table per call (UpdateCombat asks on every UNIT_FLAGS in combat), so
-- each name is asked once per session.
local atlasKnown = {}
local function AtlasAvailable(region, atlas)
  if not (region and region.SetAtlas and type(atlas) == "string" and atlas ~= "") then
    return false
  end
  local known = atlasKnown[atlas]
  if known == nil then
    local textureAPI = C_Texture
    known = textureAPI ~= nil and type(textureAPI.GetAtlasInfo) == "function"
      and textureAPI.GetAtlasInfo(atlas) ~= nil
    atlasKnown[atlas] = known
  end
  return known
end

local AdoptRegion, AnchorRegion, ApplyRestingFlipbook, ApplyTextColor, ClampLayer, EnsureText, EnsureTexture, LayoutRegion,
  SetAtlas, SetShown, SetTexCoord, SetText, SetTexture, StopRestingFlipbook
AdoptRegion, AnchorRegion, ApplyRestingFlipbook, ApplyTextColor, ClampLayer, EnsureText, EnsureTexture, LayoutRegion, SetAtlas,
  SetShown, SetTexCoord, SetText, SetTexture, StopRestingFlipbook = RequireFactory("StatusRegions")(
  SetFont, Apply, ApplyText, ApplyTexture, CreateFrame, Layers, MSUF, Media, PixelLayoutRegion, floor, issecretvalue, tonumber,
    AtlasAvailable
)

-- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
-- Keep late Client resolution and the original nil-client atlas fallback.
function Runtime.ApplyForeverLevelBadge(frame, spec, cfg)
  local badge = frame and frame.levelBackdrop
  if not (frame and cfg and cfg.foreverBadge == true) then
    SetShown(badge, false)
    SetShown(frame and frame.levelBackdropRing, false)
    return nil
  end
  local atlas = "UI-HUD-UnitFrame-SmallCircle"
  local getAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
  local useNativeAtlas = MSUF.Client.IsForever == true
    or (getAtlasInfo and getAtlasInfo(atlas)) ~= nil
  local holder = AdoptRegion(frame, badge, cfg.layer)
  if not badge then
    badge = PixelLayoutRegion((holder or frame):CreateTexture(nil, "OVERLAY", nil, -1))
    badge:Hide()
    frame.levelBackdrop = badge
  end
  if useNativeAtlas and badge._msufStatusAtlas ~= atlas then
    badge:SetAtlas(atlas)
    badge._msufStatusAtlas = atlas
    badge._msufStatusTexture = nil
    if badge.SetVertexColor then badge:SetVertexColor(1, 1, 1, 1) end
  elseif not useNativeAtlas then
    local texture = "Interface\\AddOns\\" .. (addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\circle_mask.tga"
    if badge._msufStatusTexture ~= texture then
      badge:SetTexture(texture)
      badge._msufStatusTexture = texture
      badge._msufStatusAtlas = nil
    end
    if badge.SetVertexColor then badge:SetVertexColor(0.025, 0.025, 0.025, 0.98) end
  end
  local fontSize = tonumber(cfg.size) or 14
  local size = floor((fontSize * 2.5) + 0.5)
  if size < 28 then size = 28 end
  if badge._msufStatusSize ~= size then
    badge:SetSize(size, size)
    badge._msufStatusSize = size
  end
  local numberSub = ClampLayer(cfg.layer, 7) - 1
  if numberSub > 7 then numberSub = 7 end
  local sub = numberSub - 2
  if badge.SetDrawLayer and badge._msufStatusLayer ~= sub then
    badge:SetDrawLayer("OVERLAY", sub)
    badge._msufStatusLayer = sub
  end
  local alpha = spec and spec.status and spec.status.alpha or 1
  if badge.SetAlpha and badge._msufStatusAlpha ~= alpha then
    badge:SetAlpha(alpha)
    badge._msufStatusAlpha = alpha
  end
  AnchorRegion(badge, frame, cfg)
  local ring = frame.levelBackdropRing
  if useNativeAtlas then
    SetShown(ring, false)
  else
    if not ring then
      ring = PixelLayoutRegion((holder or frame):CreateTexture(nil, "OVERLAY", nil, 0))
      ring:Hide()
      frame.levelBackdropRing = ring
    end
    local ringTexture = "Interface\\AddOns\\" .. (addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Borders\\msuf_portrait_ring_circle.tga"
    if ring._msufStatusTexture ~= ringTexture then
      ring:SetTexture(ringTexture)
      ring._msufStatusTexture = ringTexture
    end
    if ring.SetVertexColor then ring:SetVertexColor(1, 0.82, 0.3, 1) end
    if ring._msufStatusSize ~= size then
      ring:SetSize(size, size)
      ring._msufStatusSize = size
    end
    if ring.SetDrawLayer and ring._msufStatusLayer ~= sub + 1 then
      ring:SetDrawLayer("OVERLAY", sub + 1)
      ring._msufStatusLayer = sub + 1
    end
    if ring.SetAlpha and ring._msufStatusAlpha ~= alpha then
      ring:SetAlpha(alpha)
      ring._msufStatusAlpha = alpha
    end
    AnchorRegion(ring, frame, cfg)
  end
  return badge
end

local BindStatusLevelBadge
BindStatusLevelBadge = RequireFactory("StatusLevelBadge")(
  BoolTrue, FreshUnitState, nil, ReadUnitClassCached, Runtime, SafeNumber, SetShown, SetText, UnitExistsRuntime, UnitLevel, UnitRace,
    issecretvalue, tostring, type
)

-- Boss-number updates retain their original inline callable gate.
function Runtime.UpdateBossNumber(frame, status)
  local cfg = status and status.bossNumber
  local fs = frame and frame.bossNumberText
  local unit = frame and frame.MSUFUnitKey
  local index = type(GetBossIndexFromToken) == "function" and GetBossIndexFromToken(unit) or nil
  if not (cfg and cfg.enabled == true and fs and index) then
    SetShown(fs, false)
    return
  end
  SetText(fs, tostring(index))
  SetShown(fs, true)
end

local function StatusApplyRoleTexture(tex, cfg, status, role)
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
  local resolver = PublicAPI.GetRoleStatusIconTexture
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

local function StatusEffectiveStatusIconStyle(cfg, status)
  local style = cfg and cfg.style
  if type(style) ~= "string" or style == "" or style == "DEFAULT" then
    style = status and status.iconStyle
  end
  if type(style) ~= "string" or style == "" or style == "DEFAULT" or style == "BLIZZARD" then
    return nil
  end
  return style
end

local function StatusApplyStatusIconPackTexture(tex, cfg, status, iconType, variant)
  if not tex then return false end
  if cfg and type(cfg.customIcon) == "string" and cfg.customIcon ~= "" then
    SetTexture(tex, cfg.customIcon)
    SetTexCoord(tex, 0, 1, 0, 1)
    return true
  end
  local style = StatusEffectiveStatusIconStyle(cfg, status)
  if not style then return false end
  local resolver = PublicAPI.GetStatusIconTexture
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
    local resolver = assist and PublicAPI.GetAssistStatusIconTexture
      or PublicAPI.GetLeaderStatusIconTexture
    if type(resolver) == "function" then
      local path, l, r, t, b = resolver(style, status and status.useMidnight == true)
      if type(path) == "string" and path ~= "" then
        SetTexture(tex, path)
        SetTexCoord(tex, l or 0, r or 1, t or 0, b or 1)
        return
      end
    end
  end
  local atlas = assist and Media.ASSIST_ATLAS or Media.LEADER_ATLAS
  if AtlasAvailable(tex, atlas) then
    SetAtlas(tex, atlas)
  else
    SetTexture(tex, assist and Media.ASSIST_TEXTURE or Media.LEADER_TEXTURE)
    SetTexCoord(tex, 0, 1, 0, 1)
  end
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

local ApplyRoleTexture, ApplyStateOrPackIconTexture, ApplyStatusIconPackTexture, HideAFKTimerText, BindStatusIndicatorArt
ApplyRoleTexture, ApplyStateOrPackIconTexture, ApplyStatusIconPackTexture, HideAFKTimerText,
  BindStatusIndicatorArt = RequireFactory("StatusIndicatorArt")(
  StatusApplyRoleTexture, StatusApplyStatusIconPackTexture, AdoptRegion, nil, ApplyRestingFlipbook, AtlasAvailable, BoolTrue, EnsureText,
    FreshUnitState, GetRaidTargetIndex, IsResting, LayoutRegion, MSUF, Media, ReadConnectedCached, ReadDeadCached, Runtime,
    SYMBOL_PATH_CACHE, SafeNumber, SetAtlas, SetRaidTargetIconTexture, SetShown, SetTexCoord, SetText, SetTexture, StopRestingFlipbook, UF,
    UnitAffectingCombat, UnitClassification, UnitExistsRuntime, UnitFactionGroup, UnitHasIncomingResurrection, UnitIsAFK, UnitIsDND,
    UnitIsGhost, UnitIsGroupAssistant, UnitIsGroupLeader, UnitIsMercenary, UnitIsPVP, UnitIsPVPFreeForAll, UnitIsPlayerRuntime, UnitLevel,
    VALID_STATE_SYMBOLS, find, issecretvalue, type, ApplyLeaderTexture, RefreshHealthAfterGoneStatus
)

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
  { "raidMarker", "raidTargetIcon", "raidIcon", { "raidIcon", "raidTargetIcon" }, { "raidTargetIcon", "raidMarkerIndicator" }, Media.RAID_MARKER_TEXTURE },
  { "role", "roleIcon" },
  { "leader", "LeaderIndicator", "leaderIcon", { "leaderIcon", "LeaderIndicator" }, { "LeaderIndicator", "leaderIcon" } },
  { "assist", "assistIcon" },
  { "level", "levelText", nil, nil, nil, nil, true },
  { "bossNumber", "bossNumberText", nil, nil, nil, nil, true },
  { "race", "raceText", nil, nil, nil, nil, true },
  { "classText", "classStatusText", nil, nil, nil, nil, true },
  { "raidGroup", "raidGroupNameText", nil, nil, nil, nil, true },
  { "elite", "eliteIcon" },
  { "statusText", "statusIndicatorText", nil, nil, nil, nil, true },
  { "combat", "combatStateIndicatorIcon", nil, nil, nil, nil, nil, "combat" },
  { "resting", "restingIndicatorIcon", nil, nil, nil, nil, nil, "resting" },
  { "incomingRes", "incomingResIndicatorIcon", "resurrectIcon", { "resurrectIcon", "incomingResIndicatorIcon" }, { "incomingResIndicatorIcon",
    "IncomingResIndicator" }, nil, nil, "incomingRes" },
  { "pvp", "pvpIndicatorIcon", "pvpIcon", { "pvpIcon", "pvpIndicatorIcon" }, { "pvpIndicatorIcon", "pvpIcon" } },
  { "stance", "stanceIndicatorText", nil, nil, nil, nil, true },
  { "readyCheck", "readyCheckIcon" },
  { "summon", "summonIcon", nil, nil, nil, nil, nil, nil, true },
  { "phase", "phaseIcon", nil, nil, nil, Media.PHASE_TEXTURE, nil, nil, nil, true },
}

local NAME_FONT_STATUS = {
  level = true,
  bossNumber = true,
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
  if def[1] == "level" then
    HideField(frame, "levelBackdrop")
    HideField(frame, "levelBackdropRing")
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
  if key == "level" then Runtime.ApplyForeverLevelBadge(frame, spec, cfg) end
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
  -- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
  SetTexture(tex, Media.RAID_MARKER_TEXTURE)
  SetRaidTargetIconTexture(tex, index)
  tex._msufStatusL, tex._msufStatusR, tex._msufStatusT, tex._msufStatusB = nil, nil, nil, nil
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
  if issecretvalue(role) == true then role = nil end
  if not role then
    if gf and type(gf.GetUnitGroupRole) == "function" then
      role = gf.GetUnitGroupRole(unit)
    else
      if UnitGroupRolesAssigned and unit then role = UnitGroupRolesAssigned(unit) end
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
    -- Combat overlays update visuals now; MarkDirty applies OOC and defers layout in combat.
    if gf and type(gf.MarkDirty) == "function" then
      gf.MarkDirty(frame, (gf.DIRTY_GEOMETRY or 0x01) + (gf.DIRTY_LAYOUT or 0x20))
    end
  end
  return hidden
end

local CancelReadyCheckTimer, RaidGroupText

CancelReadyCheckTimer, RaidGroupText = RequireFactory("StatusGroupRuntime")(
  UpdatePowerRoleVisibility, ApplyRoleTexture, ApplyStatusIconPackTexture, C_IncomingSummon, C_Timer, FreshUnitState, GetRaidRosterInfo,
    GetReadyCheckStatus, GetTime, InCombatLockdown, MSUF, Media, ReadUnitIsPlayerCached, ReadyCheckQueue, Runtime, SUMMON_TEXTURES,
    SafeNumber, SetShown, SetTexCoord, SetText, SetTexture, UnitExistsRuntime, UnitGroupRolesAssigned, UnitInRaid, UnitIsPlayerRuntime,
    UnitPhaseReason, issecretvalue, tostring, type
)




-- Preserve the original phase order and secret gates; full rationale is in docs/uf-responsibility-notes.md.
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
  if frame._msufStanceTextValue == text and fs._msufShown == true then
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
    Runtime.UpdateStatusText(frame, status, "MSUF_ELEMENT_APPLY")
  end
end

--- A preview scene frame (UF.ApplySceneSpec): the region layout without the state pass, which asks the client about
--- the unit; the scene paints its sample status itself.
function Status.SceneApply(frame, spec)
  frame._msufStatusTextValue = nil
  frame._msufStatusTextLayout = nil
  frame._msufAFKTimerLayout = nil
  ApplyConfiguredRegions(frame, spec)
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

Runtime.RAID_MARKER_EVENTS = { "RAID_TARGET_UPDATE" }
Runtime.LEADER_EVENTS = { "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }
Runtime.LEVEL_EVENTS = { "UNIT_LEVEL" }
Runtime.LEVEL_UNITLESS_EVENTS = { "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED" }
Runtime.LEVEL_COLOR_EVENTS = { "UNIT_LEVEL", "UNIT_FACTION" }
Runtime.IDENTITY_COLOR_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION" }
Runtime.IDENTITY_NAME_EVENTS = { "UNIT_NAME_UPDATE" }
Runtime.IDENTITY_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_LEVEL" }
Runtime.RAID_GROUP_EVENTS = { "GROUP_ROSTER_UPDATE" }
Runtime.ELITE_EVENTS = { "UNIT_CLASSIFICATION_CHANGED", "UNIT_LEVEL" }
Runtime.STATUS_TEXT_EVENTS = { "UNIT_CONNECTION", "UNIT_FLAGS" }
Runtime.STATUS_TEXT_CONNECTION_EVENTS = { "UNIT_CONNECTION" }
Runtime.STATUS_TEXT_FLAGS_EVENTS = { "UNIT_FLAGS" }
-- AFK/DND edges on observed units arrive as PLAYER_FLAGS_CHANGED (a unit event
-- despite the prefix); UNIT_FLAGS never fires for another unit's AFK toggle.
Runtime.STATUS_TEXT_AFK_EVENTS = { "UNIT_CONNECTION", "UNIT_FLAGS", "PLAYER_FLAGS_CHANGED" }
Runtime.STATUS_TEXT_FLAGS_AFK_EVENTS = { "UNIT_FLAGS", "PLAYER_FLAGS_CHANGED" }
Runtime.STATUS_TEXT_UNITLESS_EVENTS = { "PLAYER_FLAGS_CHANGED" }
Runtime.STATUS_TEXT_LIFECYCLE_EVENTS = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
Runtime.STATUS_TEXT_PLAYER_UNITLESS_EVENTS = { "PLAYER_FLAGS_CHANGED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
Runtime.COMBAT_EVENTS = { "UNIT_FLAGS" }
Runtime.COMBAT_PLAYER_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
Runtime.RESTING_PLAYER_EVENTS = { "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" }
Runtime.INCOMING_RES_EVENTS = { "INCOMING_RESURRECT_CHANGED" }
Runtime.PVP_EVENTS = { "UNIT_FACTION" }

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

function Runtime.IdentityTextEvents(spec)
  if not StatusEnabled(spec, "identityText") then return EMPTY_EVENTS end
  local status = spec.status
  local needsLevel = status.level and status.level.enabled == true
  local needsName = (status.race and status.race.enabled == true)
    or (status.classText and status.classText.enabled == true)
  -- Difficulty coloring also depends on attackability, which flips on
  -- UNIT_FACTION (duels, mind control, faction-change NPCs).
  local colored = needsLevel and status.level.difficultyColor == true
  if needsLevel and needsName then return colored and Runtime.IDENTITY_COLOR_EVENTS or Runtime.IDENTITY_EVENTS end
  if needsName then return Runtime.IDENTITY_NAME_EVENTS end
  if needsLevel then return colored and Runtime.LEVEL_COLOR_EVENTS or Runtime.LEVEL_EVENTS end
  return EMPTY_EVENTS
end

function Runtime.IdentityTextUnitlessEvents(spec, frame)
  if not (frame and StatusEnabled(spec, "identityText")) then
    return EMPTY_EVENTS
  end
  local level = spec.status.level
  if not (level and level.enabled == true) then return EMPTY_EVENTS end
  -- The player frame prints its own level; every other frame only needs the
  -- player's level-up when its color is graded against it.
  if frame.MSUFUnitKey == "player" or level.difficultyColor == true then
    return Runtime.LEVEL_UNITLESS_EVENTS
  end
  return EMPTY_EVENTS
end

function Runtime.StatusTextEvents(spec, frame)
  if not StatusEnabled(spec, "statusText") then
    return EMPTY_EVENTS
  end
  local cfg = spec.status.statusText
  local player = frame and frame.MSUFUnitKey == "player"
  local needsConnection = cfg.showDead == true and player ~= true
  local needsFlags = cfg.showDead == true or cfg.showGhost == true or cfg.showAFK == true or cfg.showDND == true
    or (cfg.afkTimer and cfg.afkTimer.enabled == true)
  -- The player frame already receives PLAYER_FLAGS_CHANGED through its
  -- unitless route below; every other frame needs it unit-filtered.
  local needsPlayerFlags = player ~= true and (cfg.showAFK == true or cfg.showDND == true
    or (cfg.afkTimer and cfg.afkTimer.enabled == true))
  if needsConnection then
    if needsPlayerFlags then
      return Runtime.STATUS_TEXT_AFK_EVENTS
    end
    return needsFlags and Runtime.STATUS_TEXT_EVENTS or Runtime.STATUS_TEXT_CONNECTION_EVENTS
  end
  if needsPlayerFlags then
    return Runtime.STATUS_TEXT_FLAGS_AFK_EVENTS
  end
  return needsFlags and Runtime.STATUS_TEXT_FLAGS_EVENTS or EMPTY_EVENTS
end

function Runtime.StatusTextUnitlessEvents(spec, frame)
  if not StatusEnabled(spec, "statusText") then
    return EMPTY_EVENTS
  end
  if not (frame and frame.MSUFUnitKey == "player") then
    return EMPTY_EVENTS
  end
  local cfg = spec.status.statusText
  local needsFlags = cfg.showAFK == true or cfg.showDND == true or (cfg.afkTimer and cfg.afkTimer.enabled == true)
  local needsLifecycle = cfg.showDead == true or cfg.showGhost == true
  if needsFlags and needsLifecycle then
    return Runtime.STATUS_TEXT_PLAYER_UNITLESS_EVENTS
  elseif needsFlags then
    return Runtime.STATUS_TEXT_UNITLESS_EVENTS
  elseif needsLifecycle then
    return Runtime.STATUS_TEXT_LIFECYCLE_EVENTS
  end
  return EMPTY_EVENTS
end

function Runtime.PVPEvents(spec)
  return StatusEnabled(spec, "pvp") and Runtime.PVP_EVENTS or EMPTY_EVENTS
end

function Runtime.CombatEvents(spec, frame)
  if frame and frame.MSUFUnitKey == "player" then
    return EMPTY_EVENTS
  end
  return StatusEnabled(spec, "combat") and Runtime.COMBAT_EVENTS or EMPTY_EVENTS
end

Runtime.EMPTY_EVENTS = EMPTY_EVENTS
Runtime.StatusEnabled = StatusEnabled
Runtime.HideField = HideField
Runtime.ApplyConfiguredRegions = ApplyConfiguredRegions
Runtime.RefreshNameRelativeAnchors = RefreshNameRelativeAnchors
Runtime.CancelReadyCheckTimer = CancelReadyCheckTimer
Runtime.UpdatePowerRoleVisibility = UpdatePowerRoleVisibility
Runtime.UpdateLevel = Runtime.UpdateIdentityTexts
Runtime.RaidGroupText = RaidGroupText
MSUF.UFStatusRuntime = Runtime

local StatusStructure = {}
StatusStructure.GetEvents = Status.GetEvents
StatusStructure.GetUnitlessEvents = Status.GetUnitlessEvents
StatusStructure.Create = Status.Create
StatusStructure.Apply = Status.Apply
StatusStructure.SceneApply = Status.SceneApply
StatusStructure.Disable = Status.Disable
StatusStructure.IsEnabled = Status.IsEnabled

UF.RegisterElement("StatusIndicators", StatusStructure)

local function RegisterStatusIndicator(def)
  -- Regions are created by StatusIndicators immediately before these child
  -- elements are applied. Seed each child once on every spec apply; afterwards
  -- its narrow event route and the unit-identity path keep it current.
  local element = { UpdateOnApply = true }
  local name, key, events, unitlessEvents = def.name, def.key, def.events, def.unitlessEvents
  local update, hide = def.update, def.hide
  local noGroup, playerOnly, getEvents = def.noGroup, def.playerOnly, def.getEvents
  local getUnitlessEvents, playerUnitlessEvents, updateWithEvent = def.getUnitlessEvents, def.playerUnitlessEvents, def.updateWithEvent

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

  element.Routes = def.routes
  UF.RegisterElement(name, element)
end

-- Disable rationale: docs/uf-responsibility-notes.md.
local STATUS_INDICATOR_DEFS = {
  { name = "RaidMarkerIndicator", routes = { events = true, identity = true }, key = "raidMarker", unitlessEvents = Runtime.RAID_MARKER_EVENTS,
    update = Runtime.UpdateRaidMarker, hide = "raidTargetIcon", noGroup = true },
  { name = "LeaderIndicator", routes = { events = true, identity = true }, key = "leader", unitlessEvents = Runtime.LEADER_EVENTS,
    update = Runtime.UpdateLeaderPair, hide = { "LeaderIndicator", "leaderIcon", "assistIcon" }, noGroup = true },
  { name = "LevelIndicator", routes = { events = true, identity = true }, key = "identityText", update = Runtime.UpdateIdentityTexts,
    hide = { "levelText", "levelBackdrop", "levelBackdropRing", "raceText", "classStatusText" }, getEvents = Runtime.IdentityTextEvents,
    getUnitlessEvents = Runtime.IdentityTextUnitlessEvents },
  { name = "BossNumberIndicator", key = "bossNumber", update = Runtime.UpdateBossNumber, hide = "bossNumberText", noGroup = true },
  { name = "RaidGroupIndicator", routes = { events = true, identity = true }, key = "raidGroup", unitlessEvents = Runtime.RAID_GROUP_EVENTS,
    update = Runtime.UpdateRaidGroup, hide = "raidGroupNameText", noGroup = true },
  { name = "EliteIndicator", routes = { events = true, identity = true }, key = "elite", events = Runtime.ELITE_EVENTS,
    update = Runtime.UpdateElite, hide = "eliteIcon" },
  { name = "StatusTextIndicator", routes = { events = true, identity = true }, key = "statusText", update = Runtime.UpdateStatusText,
    hide = "statusIndicatorText", noGroup = true, getEvents = Runtime.StatusTextEvents, getUnitlessEvents = Runtime.StatusTextUnitlessEvents,
    updateWithEvent = true },
  { name = "CombatIndicator", routes = { events = true, identity = true }, key = "combat", update = Runtime.UpdateCombat,
    hide = "combatStateIndicatorIcon", getEvents = Runtime.CombatEvents, playerUnitlessEvents = Runtime.COMBAT_PLAYER_EVENTS },
  { name = "RestingIndicator", routes = { events = true, reshow = true }, key = "resting", unitlessEvents = Runtime.RESTING_PLAYER_EVENTS,
    update = Runtime.UpdateResting, hide = "restingIndicatorIcon", playerOnly = true },
  { name = "IncomingResIndicator", routes = { events = true, identity = true }, key = "incomingRes", events = Runtime.INCOMING_RES_EVENTS,
    update = Runtime.UpdateIncomingRes, hide = "incomingResIndicatorIcon", noGroup = true },
  { name = "PVPIndicator", routes = { events = true, identity = true }, key = "pvp", update = Runtime.UpdatePVP, hide = "pvpIndicatorIcon",
    noGroup = true, getEvents = Runtime.PVPEvents },
  -- Stance text events fire only on user action or a stance-bar rebuild
  -- (talents, level-up, loading screen). Never add
  -- UPDATE_SHAPESHIFT_COOLDOWN - it fires with practically every GCD and
  -- would turn this indicator into a hot path.
  { name = "StanceIndicator", routes = { events = true, reshow = true }, key = "stance",
    unitlessEvents = { "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_ENTERING_WORLD" },
    update = Status.UpdateStanceText, hide = "stanceIndicatorText", noGroup = true, playerOnly = true },
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
  MSUF.ExportPublic(STATUS_REFRESH_ALIASES[i], function(unit, reason)
    local result = RefreshStatus(unit, reason or "MSUF_STATUS")
    MSUF.EventBus:Publish("CONFIG_APPLIED", STATUS_REFRESH_ALIASES[i])
    return result
  end)
end

BindStatusLevelBadge({
  HideField = HideField,
})
BindStatusIndicatorArt({
  ApplyDefaultRaidMarkerTexture = ApplyDefaultRaidMarkerTexture,
})
