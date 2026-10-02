local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

--- UnitFrames/Engine/MSUF_UF_Config_Status.lua
---
--- Status part of the cold unit-frame config compiler: the indicator entries
--- (leader, raid marker, level, PvP, resting, ...), the dead/ghost/AFK/DND
--- status texts with the AFK timer, and the PvP indicator context with its
--- drivers. UnitFrames/Engine/MSUF_UF_Config.lua compiles every other part of
--- a unit spec, loads right after this file and calls Config.Status.

local UF = MSUF.UF
UF.Config = UF.Config or {}
local Config = UF.Config
local Shared = UF.Shared

local type = type
local tonumber = tonumber
local tostring = tostring
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local IsInInstance = _G.IsInInstance
local GetInstanceInfo = _G.GetInstanceInfo
local wipe = _G.wipe or table.wipe
local Clamp01 = UF.Clamp01
local Number = UF.NumberWithFallback
local Bool = UF.BoolWithFallback

local function ClampStatusLayer(value, fallback)
  value = Number(value, fallback or 7)
  value = math.floor(value + 0.5)
  if value < 0 then
    return 0
  elseif value > 30 then
    return 30
  end
  return value
end

local function StatusBool(conf, general, key, fallback, legacyKey)
  local value = conf and conf[key]
  if value == nil and legacyKey then
    value = conf and conf[legacyKey]
  end
  if value == nil then
    value = general and general[key]
    if value == nil and legacyKey then
      value = general and general[legacyKey]
    end
  end
  return Bool(value, fallback)
end

local Secrets = MSUF.Secrets or {}
local PlainTrue = Secrets.PlainTrue

local function APIBool(fn, ...)
  if type(fn) ~= "function" then
    return false
  end
  return PlainTrue(fn(...)) == true
end

local function CurrentInstanceType()
  if IsInInstance then
    local _, instanceType = IsInInstance()
    if type(instanceType) == "string" and instanceType ~= "" then
      return instanceType
    end
  end
  if GetInstanceInfo then
    local _, instanceType = GetInstanceInfo()
    if type(instanceType) == "string" and instanceType ~= "" then
      return instanceType
    end
  end
  return nil
end

local _pvpContextKnown, _pvpContextActive = false, false

local function UnitFramePVPContextualDisabled()
  local gameRules = _G.C_GameRules
  local enum = _G.Enum
  local rule = enum and enum.GameRule and enum.GameRule.UnitFramePvPContextualDisabled
  return gameRules and type(gameRules.IsGameRuleActive) == "function" and rule ~= nil
    and APIBool(gameRules.IsGameRuleActive, rule)
end

local function ComputePVPIndicatorContextActive(warModeOverride)
  if UnitFramePVPContextualDisabled() then return false end
  local instanceType = CurrentInstanceType()
  if instanceType == "pvp" or instanceType == "arena" then
    return true
  elseif instanceType == "party" or instanceType == "raid" then
    return false
  end

  -- WAR_MODE_STATUS_UPDATE carries the new desired state. Treat it as the
  -- authoritative boundary so a still-active deactivation timer cannot keep
  -- the compiled UF/GF PvP paths warm after War Mode was switched off.
  if warModeOverride ~= nil then
    return warModeOverride == true
  end

  local cpvp = _G.C_PvP
  if not cpvp then return false end
  -- This indicator is intentionally a PvP-mode feature, not a general
  -- UnitIsPVP flag display. Outside War Mode, arenas and battlegrounds its
  -- complete UF/GF runtime stays uncompiled even when the profile enables it.
  if type(cpvp.IsWarModeDesired) == "function" then
    return APIBool(cpvp.IsWarModeDesired)
  end
  return APIBool(cpvp.IsWarModeActive)
end

function UF.InvalidatePVPIndicatorContext()
  _pvpContextKnown = false
end

function UF.PVPIndicatorContextActive()
  if not _pvpContextKnown then
    _pvpContextActive = ComputePVPIndicatorContextActive() == true
    _pvpContextKnown = true
  end
  return _pvpContextActive == true
end

local PVP_CONTEXT_REFRESH_ELEMENTS = { "StatusIndicators", "PVPIndicator", "GroupStatusRuntime" }
-- Classic only (assigned below): repaint the context-gated indicators in place.
local RepaintPVPIndicators
local PVP_CONTEXT_FORCE_EVENTS = {
  ACTIVE_GAME_MODE_UPDATED = true,
  PLAYER_ENTERING_WORLD = true,
  WAR_MODE_STATUS_UPDATE = true,
}

function UF.RefreshPVPIndicatorContext(reason, force, warModeOverride)
  local oldKnown, oldActive = _pvpContextKnown, _pvpContextActive
  local active
  if warModeOverride ~= nil then
    active = ComputePVPIndicatorContextActive(warModeOverride == true) == true
    _pvpContextActive = active
    _pvpContextKnown = true
  else
    UF.InvalidatePVPIndicatorContext()
    active = UF.PVPIndicatorContextActive()
  end
  if force ~= true and oldKnown and oldActive == active then
    return false
  end
  -- Classic compiles the indicators whenever configured and gates them on this
  -- cached context at runtime, so a context flip, mid-combat included, is only
  -- a repaint; a recompile would wait for combat to end.
  if RepaintPVPIndicators then
    RepaintPVPIndicators()
    return true
  end
  if UF.RefreshElements then
    UF.RefreshElements(nil, PVP_CONTEXT_REFRESH_ELEMENTS, reason or "MSUF_PVP_CONTEXT")
  end
  local gf = MSUF.GF
  if gf then
    if gf.RefreshVisuals then
      gf.RefreshVisuals(nil, gf.DIRTY_VISUAL)
    elseif gf.RefreshAll then
      gf.RefreshAll()
    end
  end
  return true
end

local function RegisterPVPContextEvent(frame, event)
  frame:RegisterEvent(event)
end

--- Classic flavors (Vanilla, TBC, Mists) compile through this file too. Their few
--- differences are gated on this fact, read once at load; Mainline never enters them.
local IS_CLASSIC_FAMILY = MSUF.Client ~= nil and MSUF.Client.Family == "Classic"

--- Classic clients have no War Mode: the context follows the player's own PvP flag
--- (UnitIsPVP, free-for-all, the flag timer), which also flips mid-combat. The
--- unit and group compilers therefore build the indicator whenever it is
--- configured (pvp.contextGated), Runtime.UpdatePVP hides it outside the context,
--- and a context flip repaints the indicators in place, in combat too. Claiming
--- the driver slot here skips the Mainline driver below.
if IS_CLASSIC_FAMILY then
  RepaintPVPIndicators = function()
    local runtime = MSUF.UFStatusRuntime
    local update = runtime and runtime.UpdatePVP
    if type(update) ~= "function" then return end
    local frames = UF.attachedFrameList
    for i = 1, #frames do
      local frame = frames[i]
      local status = frame._msufStatusIndicatorStatus or frame._msufGFStatusRuntimeStatus
      local pvp = status and status.pvp
      if pvp and pvp.enabled == true and pvp.contextGated == true then
        update(frame, status)
      end
    end
  end
  local UnitIsPVP, UnitIsPVPFreeForAll, IsPVPTimerRunning = _G.UnitIsPVP, _G.UnitIsPVPFreeForAll, _G.IsPVPTimerRunning
  ComputePVPIndicatorContextActive = function()
    local instanceType = CurrentInstanceType()
    if instanceType == "pvp" or instanceType == "arena" then
      return true
    elseif instanceType == "party" or instanceType == "raid" then
      return false
    end
    local cpvp = _G.C_PvP
    if cpvp and (APIBool(cpvp.IsWarModeActive) or APIBool(cpvp.IsWarModeDesired)) then
      return true
    end
    return APIBool(UnitIsPVPFreeForAll, "player")
      or APIBool(UnitIsPVP, "player")
      or APIBool(IsPVPTimerRunning)
  end
  if not UF.pvpIndicatorContextDriver then
    local pvpDriver = CreateFrame("Frame")
    pvpDriver:SetScript("OnEvent", function(_, event, unit)
      -- PLAYER_ENTERING_WORLD's first payload argument is isInitialLogin, a
      -- boolean, not a unit token. Filtering it like a unit swallowed the one
      -- forced refresh at the initial login, which is the only pass that seeds
      -- the PvP context before the first frame apply.
      local forced = event == "PLAYER_ENTERING_WORLD"
      if not forced and unit and unit ~= "player" then
        return
      end
      UF.RefreshPVPIndicatorContext("MSUF_PVP_CONTEXT_" .. tostring(event), forced)
    end)
    local supportsEvent = MSUF.Client.SupportsEvent
    local function RegisterClassicPVPContextEvent(event, unit)
      if type(supportsEvent) == "function" and not supportsEvent(event) then return end
      if unit then
        pvpDriver:RegisterUnitEvent(event, unit)
      else
        pvpDriver:RegisterEvent(event)
      end
    end
    RegisterClassicPVPContextEvent("PLAYER_ENTERING_WORLD")
    RegisterClassicPVPContextEvent("ZONE_CHANGED_NEW_AREA")
    RegisterClassicPVPContextEvent("PVP_TIMER_UPDATE")
    RegisterClassicPVPContextEvent("PLAYER_FLAGS_CHANGED")
    RegisterClassicPVPContextEvent("WAR_MODE_STATUS_UPDATE")
    RegisterClassicPVPContextEvent("UNIT_FACTION", "player")
    UF.pvpIndicatorContextDriver = pvpDriver
  end
end

if not UF.pvpIndicatorContextDriver then
  local pvpDriver = CreateFrame("Frame")
  pvpDriver:SetScript("OnEvent", function(_, event, arg1)
    -- This driver owns cold recompilation only. PvP textures already have their
    -- native per-frame event routing, so never query context or rebuild UF/GF
    -- specs in combat.
    if InCombatLockdown and InCombatLockdown() then
      return
    end
    local force = PVP_CONTEXT_FORCE_EVENTS[event] == true
    local warModeOverride
    if event == "WAR_MODE_STATUS_UPDATE" then
      warModeOverride = PlainTrue(arg1) == true
    end
    -- This is a compile boundary, not just a repaint: false disables the
    -- cached UF status path and the GF runtime/event path before both refresh.
    UF.RefreshPVPIndicatorContext(
      "MSUF_PVP_CONTEXT_" .. tostring(event),
      force,
      warModeOverride
    )
  end)
  RegisterPVPContextEvent(pvpDriver, "ACTIVE_GAME_MODE_UPDATED")
  RegisterPVPContextEvent(pvpDriver, "PLAYER_ENTERING_WORLD")
  RegisterPVPContextEvent(pvpDriver, "ZONE_CHANGED_NEW_AREA")
  RegisterPVPContextEvent(pvpDriver, "WAR_MODE_STATUS_UPDATE")
  UF.pvpIndicatorContextDriver = pvpDriver
end

local function StatusNumber(conf, general, key, fallback, legacyKey)
  local value = conf and conf[key]
  if value == nil and legacyKey then
    value = conf and conf[legacyKey]
  end
  if value == nil then
    value = general and general[key]
    if value == nil and legacyKey then
      value = general and general[legacyKey]
    end
  end
  return Number(value, fallback)
end

local function StatusString(conf, general, key, fallback, legacyKey)
  local value = conf and conf[key]
  if (type(value) ~= "string" or value == "") and legacyKey then
    value = conf and conf[legacyKey]
  end
  if type(value) ~= "string" or value == "" then
    value = general and general[key]
    if (type(value) ~= "string" or value == "") and legacyKey then
      value = general and general[legacyKey]
    end
  end
  if type(value) ~= "string" or value == "" then
    value = fallback
  end
  return value or ""
end

local function StatusAllowed(key, id)
  if id == "leader" or id == "assist" or id == "combat" or id == "incomingRes" then
    return key == "player" or key == "target"
  elseif id == "pvp" then
    return key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "focustarget" or key == "pettarget"
      or key == "arena"
  elseif id == "resting" or id == "stance" then
    return key == "player"
  elseif id == "raidGroup" then
    return key == "player" or key == "target" or key == "targettarget" or key == "focustarget" or key == "pettarget" or key == "focus"
  elseif id == "elite" then
    return key == "target" or key == "focus" or key == "targettarget" or key == "focustarget" or key == "pettarget" or key == "boss"
  elseif id == "petHappiness" or id == "petXP" then
    return key == "pet"
  elseif id == "threat" then
    return key == "target" or key == "focus" or key == "boss"
  end
  return true
end

local function CompileStatusEntry(status, id, conf, general, key, showKey, fallbackShow, sizeKey, fallbackSize, anchorKey, fallbackAnchor, xKey, fallbackX, yKey, fallbackY, layerKey, fallbackLayer, legacyLayerKey)
  local entry = status[id] or {}
  status[id] = entry
  entry.enabled = StatusAllowed(key, id) and StatusBool(conf, general, showKey, fallbackShow) or false
  entry.size = StatusNumber(conf, general, sizeKey, fallbackSize)
  entry.anchor = StatusString(conf, general, anchorKey, fallbackAnchor)
  entry.x = StatusNumber(conf, general, xKey, fallbackX)
  entry.y = StatusNumber(conf, general, yKey, fallbackY)
  entry.layer = ClampStatusLayer(StatusNumber(conf, general, layerKey, fallbackLayer, legacyLayerKey), fallbackLayer)
  return entry
end

--- Indicator text colors are stored as a complete R/G/B triple or not at all.
--- Unlike StatusNumber this read is nil-preserving on purpose: an unset triple
--- has to keep inheriting the frame's resolved font color, so profiles that
--- never picked a color are not silently pinned to white.
local function ApplyStatusColor(entry, conf, general, colorPrefix)
  local r, g, b
  if colorPrefix then
    r = conf and conf[colorPrefix .. "ColorR"]
    if r == nil then r = general and general[colorPrefix .. "ColorR"] end
    g = conf and conf[colorPrefix .. "ColorG"]
    if g == nil then g = general and general[colorPrefix .. "ColorG"] end
    b = conf and conf[colorPrefix .. "ColorB"]
    if b == nil then b = general and general[colorPrefix .. "ColorB"] end
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
  end
  if r and g and b then
    entry.colorR, entry.colorG, entry.colorB = Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1)
  else
    entry.colorR, entry.colorG, entry.colorB = nil, nil, nil
  end
  return entry
end

local function StatusEntryDef(id, showKey, showDefault, sizeKey, sizeDefault, anchorKey, anchorDefault, xKey, xDefault, yKey, yDefault, layerKey, layerDefault, style, symbol, customIcon, legacyLayerKey, colorPrefix)
  return { id, showKey, showDefault, sizeKey, sizeDefault, anchorKey, anchorDefault, xKey, xDefault, yKey, yDefault, layerKey, layerDefault, style = style, symbol = symbol, customIcon = customIcon, legacyLayerKey = legacyLayerKey, colorPrefix = colorPrefix }
end

local function PrefixedStatusDef(id, showKey, showDefault, prefix, sizeDefault, anchorDefault, xDefault, yDefault, layerDefault, style, symbol, customIcon)
  return StatusEntryDef(id, showKey, showDefault,
    prefix .. "Size", sizeDefault, prefix .. "Anchor", anchorDefault,
    prefix .. "OffsetX", xDefault, prefix .. "OffsetY", yDefault,
    prefix .. "Layer", layerDefault, style, symbol, customIcon, nil, prefix)
end

local UNIT_STATUS_ENTRY_DEFS = {
  PrefixedStatusDef("leader", "showLeaderIcon", true, "leaderIcon", 14, "TOPLEFT", 0, 3, 7, { "leaderIconStyle", "BLIZZARD" }, nil, { "leaderIconCustomIcon", "" }),
  PrefixedStatusDef("assist", "showLeaderIcon", true, "leaderIcon", 14, "TOPLEFT", 0, 3, 7, { "assistIconStyle", "BLIZZARD", "leaderIconStyle" }, nil, { "assistIconCustomIcon", "" }),
  PrefixedStatusDef("raidMarker", "showRaidMarker", true, "raidMarker", 18, "TOPLEFT", 16, 3, 7, nil, nil, { "raidMarkerCustomIcon", "" }),
  PrefixedStatusDef("level", "showLevelIndicator", true, "levelIndicator", 14, "NAMERIGHT", 0, 0, 7),
  PrefixedStatusDef("bossNumber", "showBossNumberIndicator", false, "bossNumberIndicator", 14, "TOPLEFT", 4, -4, 7),
  PrefixedStatusDef("race", "showRaceIndicator", false, "raceIndicator", 14, "NAMERIGHT", 0, 0, 7),
  PrefixedStatusDef("classText", "showClassTextIndicator", false, "classTextIndicator", 14, "NAMERIGHT", 0, 0, 7),
  StatusEntryDef("raidGroup", "showRaidGroupInName", false, "raidGroupNameSize", 12, "raidGroupNameAnchor", "NAMERIGHT", "raidGroupNameOffsetX", 3, "raidGroupNameOffsetY", 0, "raidGroupNameLayer", 5, { "raidGroupNameStyle", "PAREN" }, nil, nil, "nameTextLayer", "raidGroupName"),
  PrefixedStatusDef("elite", "showEliteIcon", true, "eliteIcon", 20, "TOPRIGHT", 2, 2, 7, nil, nil, { "eliteIconCustomIcon", "" }),
  PrefixedStatusDef("combat", "showCombatStateIndicator", true, "combatStateIndicator", 18, "TOPLEFT", 0, 0, 7, nil, { "combatStateIndicatorSymbol", "DEFAULT" }, { "combatStateIndicatorCustomIcon", "" }),
  PrefixedStatusDef("resting", "showRestingIndicator", true, "restedStateIndicator", 39, "TOPLEFT", -40, 50, 25, { "restedStateIndicatorIconStyle", "BLIZZARD" }, { "restedStateIndicatorSymbol", "rested_blizzard_animated", "restingStateIndicatorSymbol" }, { "restedStateIndicatorCustomIcon", "" }),
  PrefixedStatusDef("incomingRes", "showIncomingResIndicator", true, "incomingResIndicator", 18, "TOPRIGHT", 0, 0, 7, nil, { "incomingResIndicatorSymbol", "DEFAULT" }, { "incomingResIndicatorCustomIcon", "" }),
  PrefixedStatusDef("pvp", "showPvpIndicator", true, "pvpIndicator", 18, "TOPRIGHT", 0, 0, 7, nil, nil, { "pvpIndicatorCustomIcon", "" }),
  PrefixedStatusDef("stance", "showStanceIndicator", false, "stanceIndicator", 12, "TOP", 0, -2, 7),
}
-- Hunter pet happiness exists on WoW Forever, Classic Era and TBC, which all
-- compile here. Midnight and Mists get no entry at all.
if MSUF.Client and MSUF.Client.SupportsPetHappiness == true then
  UNIT_STATUS_ENTRY_DEFS[#UNIT_STATUS_ENTRY_DEFS + 1] =
    PrefixedStatusDef("petHappiness", "showPetHappinessIndicator", true, "petHappinessIndicator", 24, "RIGHT", -7, -4, 7)
end
-- The threat percentage text exists on WoW Forever, Classic Era and TBC (see
-- Game/Shared/UnitFrames/MSUF_UF_ThreatText.lua). Default on, in the bottom-left
-- corner that no other status element uses; Midnight and Mists get no entry.
if MSUF.Client and MSUF.Client.SupportsThreatText == true then
  UNIT_STATUS_ENTRY_DEFS[#UNIT_STATUS_ENTRY_DEFS + 1] =
    PrefixedStatusDef("threat", "showThreatIndicator", true, "threatIndicator", 11, "BOTTOMLEFT", 6, 2, 7)
end

if MSUF.Client and MSUF.Client.IsClassic == true then
  UNIT_STATUS_ENTRY_DEFS[#UNIT_STATUS_ENTRY_DEFS + 1] =
    PrefixedStatusDef("petXP", "showPetXPBar", true, "petXPBar", 8, "BOTTOM", 0, -5, 7)
end

local UNIT_STATUS_TEXT_STATE_DEFS = {
  { "statusDeadText", "statusDeadTextEnabled", "showDead", true, "statusText" },
  { "statusGhostText", "statusGhostTextEnabled", "showGhost", true, "statusGhostText" },
  { "statusAFKText", "statusAFKTextEnabled", "showAFK", false, "statusAFKText" },
  { "statusDNDText", "statusDNDTextEnabled", "showDND", false, "statusDNDText" },
}

local function CompileUnitStatusTextState(status, conf, general, def, fallbackSize)
  local id, showKey, legacyStateKey, defaultShow, prefix = def[1], def[2], def[3], def[4], def[5]
  local entry = status[id] or {}
  status[id] = entry
  local explicit = conf and conf[showKey]
  if explicit == nil then explicit = general and general[showKey] end
  if explicit == nil then
    local states = general and type(general.statusIndicators) == "table" and general.statusIndicators or nil
    local legacyState = states and states[legacyStateKey]
    if legacyState == nil then legacyState = defaultShow end
    entry.enabled = StatusBool(conf, general, "statusTextEnabled", true) and legacyState == true
  else
    entry.enabled = Bool(explicit, defaultShow)
  end
  local legacyPrefix = prefix ~= "statusText" and "statusText" or nil
  entry.size = StatusNumber(conf, general, prefix .. "Size", fallbackSize, legacyPrefix and (legacyPrefix .. "Size"))
  entry.anchor = StatusString(conf, general, prefix .. "Anchor", "CENTER", legacyPrefix and (legacyPrefix .. "Anchor"))
  entry.x = StatusNumber(conf, general, prefix .. "OffsetX", 0, legacyPrefix and (legacyPrefix .. "OffsetX"))
  entry.y = StatusNumber(conf, general, prefix .. "OffsetY", 0, legacyPrefix and (legacyPrefix .. "OffsetY"))
  entry.layer = ClampStatusLayer(StatusNumber(conf, general, prefix .. "Layer", 7, legacyPrefix and (legacyPrefix .. "Layer")), 7)
  ApplyStatusColor(entry, conf, general, prefix)
  return entry
end

local function CompileStatusEntryDef(status, conf, general, key, def, fallbackSize)
  local entry = CompileStatusEntry(status, def[1], conf, general, key,
    def[2], def[3], def[4], fallbackSize or def[5], def[6], def[7],
    def[8], def[9], def[10], def[11], def[12], def[13], def.legacyLayerKey)
  local style = def.style
  if style then
    entry.style = StatusString(conf, general, style[1], style[2])
  end
  local symbol = def.symbol
  if symbol then
    entry.symbol = StatusString(conf, general, symbol[1], symbol[2], symbol[3])
  end
  local customIcon = def.customIcon
  if customIcon then
    entry.customIcon = StatusString(conf, general, customIcon[1], customIcon[2])
  end
  ApplyStatusColor(entry, conf, general, def.colorPrefix)
  return entry
end

local function CompileUnitStatus(out, conf, general, key)
  out.status = out.status or {}
  local status = out.status
  status.key = key
  local statusAlpha = StatusNumber(conf, general, "stateIconsAlpha", 1, "statusIconsAlpha")
  if statusAlpha > 1 then
    statusAlpha = statusAlpha / 100
  end
  status.alpha = Clamp01(statusAlpha, 1)
  status.testMode = StatusBool(conf, general, "stateIconsTestMode", false, "statusIconsTestMode")
  status.useMidnight = StatusBool(conf, general, "statusIconsUseMidnightStyle", false)

  local levelSize = Number(conf.nameFontSize or general.nameFontSize, out.nameFontSize)
  -- raidGroupNameSize ships unseeded on purpose: an untouched profile keeps
  -- the inline group number at the frame's name font size, exactly as it looked
  -- while the two shared one key.
  local raidGroupSize = out.nameFontSize
  local statusTextSize = out.nameFontSize + 2
  for i = 1, #UNIT_STATUS_ENTRY_DEFS do
    local def = UNIT_STATUS_ENTRY_DEFS[i]
    local id = def[1]
    local fallbackSize = statusTextSize
    if id == "level" or id == "bossNumber" or id == "race" or id == "classText" or id == "stance" then
      fallbackSize = levelSize
    elseif id == "raidGroup" then
      fallbackSize = raidGroupSize
    elseif id == "petXP" then
      fallbackSize = nil
    elseif id == "threat" then
      -- The def's own 11 px: the text sits under the 14 px name on 30 px frames.
      fallbackSize = nil
    end
    CompileStatusEntryDef(status, conf, general, key, def, fallbackSize)
  end
  if status.petXP then
    local width = StatusNumber(conf, general, "petXPBarWidth", 80)
    if width < 8 then width = 8 elseif width > 400 then width = 400 end
    status.petXP.width = width
  end

  -- Level difficulty coloring defaults on, but a profile that already picked a
  -- level text color keeps that color until the toggle is set explicitly.
  local level = status.level
  if level then
    level.difficultyColor = StatusBool(conf, general, "levelIndicatorDifficultyColor", level.colorR == nil)
    level.difficultyColors = level.difficultyColor and Shared.ResolveLevelDifficultyColors(general) or nil
    -- WoW Forever's Camelot unitframes center the level over the stock
    -- UI-HUD-UnitFrame-SmallCircle atlas. Keep it opt-in so every existing
    -- profile remains plain text, while the same status anchor/size/layer still
    -- owns both the number and its badge.
    level.foreverBadge = StatusBool(conf, general, "levelIndicatorForeverBadge", false)
  end
  -- The threat color curve follows the same rule: on, unless the frame already
  -- picked its own threat text color. The palette is global and resolved by the
  -- threat module (Game/Shared/UnitFrames/MSUF_UF_ThreatText.lua).
  local threat = status.threat
  if threat then
    threat.colorCurve = StatusBool(conf, general, "threatIndicatorColorCurve", threat.colorR == nil)
    -- A dark plate behind the number keeps it readable on red enemy bars.
    threat.background = StatusBool(conf, general, "threatIndicatorBackground", true)
  end

  local statusTextStates = {}
  for i = 1, #UNIT_STATUS_TEXT_STATE_DEFS do
    statusTextStates[i] = CompileUnitStatusTextState(status, conf, general, UNIT_STATUS_TEXT_STATE_DEFS[i], statusTextSize)
  end
  local deadText, ghostText, afkText, dndText = statusTextStates[1], statusTextStates[2], statusTextStates[3], statusTextStates[4]
  local baseText = deadText.enabled and deadText or ghostText.enabled and ghostText
    or afkText.enabled and afkText or dndText.enabled and dndText or deadText
  local statusText = status.statusText or {}
  status.statusText = statusText
  statusText.enabled = deadText.enabled or ghostText.enabled or afkText.enabled or dndText.enabled
  statusText.size, statusText.anchor = baseText.size, baseText.anchor
  statusText.x, statusText.y, statusText.layer = baseText.x, baseText.y, baseText.layer
  statusText.colorR, statusText.colorG, statusText.colorB = baseText.colorR, baseText.colorG, baseText.colorB
  statusText.showDead, statusText.showGhost = deadText.enabled, ghostText.enabled
  statusText.showAFK, statusText.showDND = afkText.enabled, dndText.enabled
  statusText.dead, statusText.ghost, statusText.afk, statusText.dnd = deadText, ghostText, afkText, dndText

  -- AFK timer companion region: independent placement, but it only renders
  -- while the AFK state text is active, so it needs no own show-state keys.
  local afkTimer = statusText.afkTimer or {}
  statusText.afkTimer = afkTimer
  local afkTimerShow = conf and conf.statusAFKTimerEnabled
  if afkTimerShow == nil then afkTimerShow = general and general.statusAFKTimerEnabled end
  afkTimer.enabled = afkTimerShow == true
  afkTimer.size = StatusNumber(conf, general, "statusAFKTimerSize", 12)
  afkTimer.anchor = StatusString(conf, general, "statusAFKTimerAnchor", "CENTER")
  afkTimer.x = StatusNumber(conf, general, "statusAFKTimerOffsetX", 0)
  afkTimer.y = StatusNumber(conf, general, "statusAFKTimerOffsetY", -14)
  afkTimer.layer = ClampStatusLayer(StatusNumber(conf, general, "statusAFKTimerLayer", 7), 7)
  ApplyStatusColor(afkTimer, conf, general, "statusAFKTimer")
  if afkTimer.colorR == nil then
    afkTimer.colorR, afkTimer.colorG, afkTimer.colorB = afkText.colorR, afkText.colorG, afkText.colorB
  end

  local pvp = status.pvp
  if IS_CLASSIC_FAMILY then
    pvp.contextGated = pvp.enabled == true or nil
  elseif pvp.enabled and UF.PVPIndicatorContextActive and not UF.PVPIndicatorContextActive() then
    pvp.enabled = false
    pvp.contextDisabled = true
  end

  local statusEnabled = false
  for i = 1, #UNIT_STATUS_ENTRY_DEFS do
    local entry = status[UNIT_STATUS_ENTRY_DEFS[i][1]]
    statusEnabled = statusEnabled or (entry and entry.enabled == true)
  end
  statusEnabled = statusEnabled or statusText.enabled
  status.enabled = statusEnabled
end

--- The status compiler and the one layer clamp the text and power compilers
--- share with it.
Config.Status = {
  ClampLayer = ClampStatusLayer,
  CompileUnit = CompileUnitStatus,
}
