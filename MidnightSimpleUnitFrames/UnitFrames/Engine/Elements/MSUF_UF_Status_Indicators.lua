-- UF responsibility owner; dependencies bind once before runtime.
local _, MSUF = ...
MSUF.UFModuleFactories = MSUF.UFModuleFactories or {}

MSUF.UFModuleFactories.StatusIndicatorArt = function(
  StatusApplyRoleTexture, StatusApplyStatusIconPackTexture, AdoptRegion, ApplyDefaultRaidMarkerTexture, ApplyRestingFlipbook,
    AtlasAvailable, BoolTrue, EnsureText, FreshUnitState, GetRaidTargetIndex, IsResting, LayoutRegion, MSUF, Media, ReadConnectedCached,
    ReadDeadCached, Runtime, SYMBOL_PATH_CACHE, SafeNumber, SetAtlas, SetRaidTargetIconTexture, SetShown, SetTexCoord, SetText, SetTexture,
    StopRestingFlipbook, UF, UnitAffectingCombat, UnitClassification, UnitExistsRuntime, UnitFactionGroup, UnitHasIncomingResurrection,
    UnitIsAFK, UnitIsDND, UnitIsGhost, UnitIsGroupAssistant, UnitIsGroupLeader, UnitIsMercenary, UnitIsPVP, UnitIsPVPFreeForAll,
    UnitIsPlayerRuntime, UnitLevel, VALID_STATE_SYMBOLS, find, issecretvalue, type, ApplyLeaderTexture, RefreshHealthAfterGoneStatus, SUMMON_TEXTURES
)
local ApplyRoleTexture = StatusApplyRoleTexture
local ApplyStatusIconPackTexture = StatusApplyStatusIconPackTexture
local IS_FOREVER = MSUF.Client.IsForever == true
-- A skull level on Forever can also mean a high-level normal NPC.
local EliteFallbackUnitLevel = not IS_FOREVER and UnitLevel

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
  local path = Media.SYMBOL_BASE .. folder .. "\\" .. symbol .. suffix
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
    if AtlasAvailable(tex, Media.COMBAT_ATLAS) then
      SetAtlas(tex, Media.COMBAT_ATLAS)
    else
      SetTexture(tex, Media.STATE_TEXTURE)
      SetTexCoord(tex, 0.5, 1, 0, 0.5)
    end
  elseif kind == "resting" then
    SetTexture(tex, Media.STATE_TEXTURE)
    SetTexCoord(tex, 0, 0.5, 0, 0.5)
  elseif kind == "incomingRes" then
    SetTexture(tex, Media.READY_REZ_TEXTURE)
    SetTexCoord(tex, 0, 1, 0, 1)
  end
end

local function PVPAtlasForFaction(factionGroup)
  return Media.PVP_ATLAS_BY_FACTION[factionGroup]
end

local function PVPFallbackTextureForAtlas(atlas)
  return Media.PVP_TEXTURE_BY_ATLAS[atlas]
end

local function ResolvePVPAtlas(frame, unit, unitState, showFaction)
  if not (unit and UnitExistsRuntime(unit, unitState, frame)) then
    return nil
  end
  if UnitIsPVPFreeForAll and BoolTrue(UnitIsPVPFreeForAll(unit)) then
    return Media.PVP_FFA_ATLAS
  end
  if not (UnitIsPVP and UnitFactionGroup) then return nil end
  local flagged = UnitIsPVP(unit)
  if issecretvalue(flagged) == true then return nil end
  if flagged ~= true and flagged ~= 1 then
    if not (showFaction and flagged == false and UnitIsPlayerRuntime(unit, unitState, frame)) then return nil end
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
  return PVPAtlasForFaction(factionGroup) or Media.PVP_ALLIANCE_ATLAS
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

local function ApplyStateOrPackIconTexture(tex, kind, cfg, status, variant, playAnimation)
  if kind == "resting" then
    if cfg and cfg.symbol == Media.RESTING_ANIMATED_SYMBOL
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

function Runtime.UpdateRaidMarker(frame, status)
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

function Runtime.UpdateLeader(frame, status)
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

function Runtime.UpdateLeaderPair(frame, status)
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
    if leaderTex and leaderTex._msufShown ~= false then SetShown(leaderTex, false) end
    if assistTex and assistTex._msufShown ~= false then SetShown(assistTex, false) end
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
    and frame._msufLeaderStyle == (leaderCfg and leaderCfg.style)
    and frame._msufLeaderCustom == (leaderCfg and leaderCfg.customIcon)
    and frame._msufAssistStyle == (assistCfg and assistCfg.style)
    and frame._msufAssistCustom == (assistCfg and assistCfg.customIcon)
    and (not leaderTex or leaderTex._msufShown == (showLeader and true or false))
    and (not assistTex or assistTex._msufShown == (showAssist and true or false)) then
    return
  end
  if frame then
    frame._msufLeaderPairState = state
    frame._msufLeaderPairSerial = serial
    frame._msufLeaderStyle = leaderCfg and leaderCfg.style
    frame._msufLeaderCustom = leaderCfg and leaderCfg.customIcon
    frame._msufAssistStyle = assistCfg and assistCfg.style
    frame._msufAssistCustom = assistCfg and assistCfg.customIcon
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

local ELITE_STATE_BY_CLASSIFICATION = { worldboss = "BOSS", rareelite = "RAREELITE", rare = "RARE", elite = "ELITE" }

local function EliteState(frame, unit, unitState)
  local exists = UnitExistsRuntime(unit, unitState, frame)
  if not (UnitClassification and exists) then
    return nil
  end
  local class = UnitClassification(unit)
  if issecretvalue(class) == true then
    return nil
  end
  local state = ELITE_STATE_BY_CLASSIFICATION[class]
  if state then return state end
  if EliteFallbackUnitLevel and SafeNumber(EliteFallbackUnitLevel(unit)) == -1 then
    return "BOSS"
  end
  return nil
end

function Runtime.UpdateElite(frame, status)
  local cfg = status and status.elite
  local tex = frame.eliteIcon
  if not (cfg and cfg.enabled and tex) then
    SetShown(tex, false)
    return
  end
  local unit = frame.MSUFUnitKey
  local unitState = FreshUnitState(frame, unit)
  -- On Forever, require a known NPC before showing an automatic badge.
  if status.testMode ~= true and UnitIsPlayerRuntime(unit, unitState, frame, IS_FOREVER) == true then
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

local GetConsumptionText
if IS_FOREVER and C_UnitAuras and C_UnitAuras.GetUnitAuras then
  local GetUnitAuras = C_UnitAuras.GetUnitAuras
  local ReadConsumptionAuras = GetUnitAuras
  local ShouldAurasBeSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret
  local function SkipConsumptionAuras() end

  -- The global secrecy predicate can be false while the client refuses a
  -- unit's bulk read. World combat can create a group frame during that window.
  function Runtime.SuspendConsumptionAuraScan(suspended)
    ReadConsumptionAuras = suspended and SkipConsumptionAuras or GetUnitAuras
  end

  -- Forever 1.60.1.70862 SpellEffect and SpellInterrupts data. These are the
  -- seated regeneration auras, including food and drink combined.
  local DRINK_AURAS = {
    [430] = true, [431] = true, [432] = true, [833] = true, [1133] = true, [1135] = true,
    [1137] = true, [2639] = true, [10250] = true, [18140] = true, [22734] = true, [23698] = true,
    [24355] = true, [24707] = true, [25696] = true, [25990] = true, [26261] = true, [26263] = true,
    [26402] = true, [26473] = true, [26475] = true, [29007] = true, [29055] = true, [446714] = true,
    [461632] = true, [468767] = true, [1226808] = true, [1269354] = true, [1291782] = true, [1312719] = true,
  }
  local FOOD_AURAS = {
    [433] = true, [434] = true, [435] = true, [1127] = true, [1129] = true, [1131] = true,
    [5004] = true, [5005] = true, [5006] = true, [5007] = true, [6410] = true, [7737] = true,
    [10256] = true, [10257] = true, [18124] = true, [18229] = true, [18230] = true, [18231] = true,
    [18232] = true, [18233] = true, [18234] = true, [21149] = true, [22731] = true, [24005] = true,
    [24800] = true, [24869] = true, [25660] = true, [25695] = true, [25700] = true, [25702] = true,
    [25886] = true, [25888] = true, [26030] = true, [26260] = true, [26401] = true, [26472] = true,
    [26474] = true, [28616] = true, [29008] = true, [29073] = true, [446713] = true, [470362] = true,
    [470369] = true, [1225769] = true, [1225771] = true, [1225772] = true, [1225774] = true,
  }

  local function ClassifyConsumption(auras)
    if issecretvalue(auras) or type(auras) ~= "table" then return nil end
    local eating
    for i = 1, #auras do
      local aura = auras[i]
      if not issecretvalue(aura) and type(aura) == "table" then
        local spellID = aura.spellId
        if not issecretvalue(spellID) and type(spellID) == "number" then
          if DRINK_AURAS[spellID] then return "DRINKING" end
          if FOOD_AURAS[spellID] then eating = "EATING" end
        end
      end
    end
    return eating
  end

  GetConsumptionText = function(unit, previous, update)
    if not ShouldAurasBeSecret or ShouldAurasBeSecret() ~= false then return nil end
    -- When no consumption aura was visible, a pure addition/removal only
    -- needs the new auras. Refresh on updates because visibility can change.
    if not previous and not issecretvalue(update) and type(update) == "table" then
      local full = update.isFullUpdate
      local updated = update.updatedAuraInstanceIDs
      if not issecretvalue(full) and full == false and not issecretvalue(updated)
        and (updated == nil or #updated == 0) then
        return ClassifyConsumption(update.addedAuras)
      end
    end
    return ClassifyConsumption(ReadConsumptionAuras(unit, "HELPFUL"))
  end
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
  if cfg and (cfg.showAFK or (cfg.afkTimer and cfg.afkTimer.enabled)) and UnitIsAFK then
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
  if cfg and cfg.showConsumption then
    return frame._msufConsumptionText, "consumption"
  end
  return nil
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

local function ClearStatusText(frame, fs, keepAFKTimer)
  if not keepAFKTimer then HideAFKTimerText(frame) end
  if frame._msufStatusTextValue == nil
    and frame._msufStatusTextLayout == nil
    and fs and fs._msufShown == false then
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

function Runtime.UpdateStatusText(frame, status, event, seedHP)
  local cfg = status and status.statusText
  local fs = frame.statusIndicatorText
  local unit = frame.MSUFUnitKey
  if not (cfg and cfg.enabled and fs) then
    frame._msufConsumptionText = nil
    ClearStatusText(frame, fs)
    return
  end
  local unitState = FreshUnitState(frame, unit)
  if status.testMode ~= true
    and event == "UNIT_HEALTH"
    and frame._msufStatusTextValue == nil
    and fs._msufShown == false
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
    frame._msufConsumptionText = nil
    ClearStatusText(frame, fs)
    return
  end
  if event ~= "UNIT_HEALTH" and event ~= "MSUF_AFK_TIMER_TICK" then
    if cfg.showConsumption and GetConsumptionText and not status.testMode then
      local update = event == "UNIT_AURA" and seedHP
      frame._msufConsumptionText = GetConsumptionText(unit, frame._msufConsumptionText, update)
    else
      frame._msufConsumptionText = nil
    end
  end
  if event == "UNIT_AURA" then seedHP = nil end
  local text, state
  if status.testMode then
    if cfg.showDead then
      text, state = "DEAD", "dead"
    elseif cfg.showGhost then
      text, state = "GHOST", "ghost"
    elseif cfg.showAFK or (cfg.afkTimer and cfg.afkTimer.enabled) then
      text, state = "AFK", "afk"
    elseif cfg.showDND then
      text, state = "DND", "dnd"
    elseif cfg.showConsumption then
      text, state = "DRINKING", "consumption"
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
    elseif state == "consumption" and cfg.consumption then
      layout = cfg.consumption
    elseif cfg.dead then
      layout = cfg.dead
    end
    if layout and layout.enabled == false then
      ClearStatusText(frame, fs, state == "afk")
      UpdateAFKTimerText(frame, status, cfg, state)
      return
    end
    -- Before the unchanged early-out: the ledger ticker re-enters this
    -- function with an unchanged main text and only the duration moves.
    UpdateAFKTimerText(frame, status, cfg, state)
    if frame._msufStatusTextValue == text
      and frame._msufStatusTextLayout == layout
      and fs._msufShown == true then
      return
    end
    local oldValue = frame._msufStatusTextValue
    frame._msufStatusTextValue = text
    frame._msufStatusTextLayout = layout
    if layout ~= cfg then
      AdoptRegion(frame, fs, layout.layer)
    end
    LayoutRegion(fs, frame, frame.MSUFSpec, layout, true)
    -- text stays the state token that the
    -- health element compares; only the font string gets the translation.
    SetText(fs, MSUF.Translate(text))
    SetShown(fs, true)
    if StatusTextIsGone(oldValue) and not StatusTextIsGone(text) then
      RefreshHealthAfterGoneStatus(frame, oldValue)
    end
  else
    ClearStatusText(frame, fs)
  end
end

function Runtime.UpdateCombat(frame, status)
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

function Runtime.UpdateResting(frame, status)
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

function Runtime.UpdateIncomingRes(frame, status)
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
  if atlas == Media.PVP_HORDE_ATLAS then return "Horde" end
  if atlas == Media.PVP_FFA_ATLAS then return "FFA" end
  return "Alliance"
end

function Runtime.UpdatePVP(frame, status)
  local cfg = status and status.pvp
  local tex = frame and frame.pvpIndicatorIcon
  local unit = frame and frame.MSUFUnitKey
  if not (cfg and cfg.enabled and tex and unit) then
    SetShown(tex, false)
    return
  end
  local showFaction
  if status.testMode ~= true then
    if cfg.followsTarget then
      local allowed, openWorld = UF.TargetPVPScope()
      if not allowed then
        SetShown(tex, false)
        return
      end
      showFaction = cfg.showOpenWorldFaction and openWorld
    elseif cfg.contextGated == true and not (UF.PVPIndicatorContextActive and UF.PVPIndicatorContextActive()) then
      SetShown(tex, false)
      return
    end
  end
  local unitState = FreshUnitState(frame, unit)
  local atlas = status.testMode and ResolvePVPTestAtlas(unit) or ResolvePVPAtlas(frame, unit, unitState, showFaction)
  if atlas and ApplyStatusIconPackTexture(tex, cfg, status, "pvp", PVPVariantForAtlas(atlas)) then
    SetShown(tex, true)
  elseif ApplyPVPTexture(tex, atlas) then
    SetShown(tex, true)
  else
    SetShown(tex, false)
  end
end


--- Scene form of the indicator updates: the sample's flags into the regions StatusIndicators laid out, behind the live gates.
function Runtime.PaintSampleIndicators(frame, status, sample)
  if not status then return end
  local cfg, tex = status.raidMarker, frame.raidTargetIcon
  if tex then
    local index = cfg and cfg.enabled and sample.raidTarget or nil
    if index then
      if not ApplyStatusIconPackTexture(tex, cfg, status, "raidMarker", index) then
        ApplyDefaultRaidMarkerTexture(tex, index)
      end
      tex._msufRaidMarkerIndex = nil
    end
    SetShown(tex, index ~= nil)
  end
  local leaderCfg, assistCfg = status.leader, status.assist
  local leaderTex, assistTex = frame.leaderIcon or frame.LeaderIndicator, frame.assistIcon
  local all = sample.statusSelection == "all"
  local playerSample = sample.player == true or all
  local leader = playerSample and sample.leader == true
  local assist = playerSample and (not leader or all) and sample.assist == true
  if leaderTex then
    local show = leaderCfg and leaderCfg.enabled and leader
    if show then ApplyLeaderTexture(leaderTex, leaderCfg, status, false) end
    SetShown(leaderTex, show and true or false)
  end
  if assistTex then
    local show = assistCfg and assistCfg.enabled and assist
    if show then ApplyLeaderTexture(assistTex, assistCfg, status, true) end
    SetShown(assistTex, show and true or false)
  end
  cfg, tex = status.elite, frame.eliteIcon
  if tex then
    local state = cfg and cfg.enabled and (sample.player ~= true or all) and ELITE_STATE_BY_CLASSIFICATION[sample.classification] or nil
    if not IS_FOREVER and state == nil and cfg and cfg.enabled and sample.player ~= true and sample.level == -1 then state = "BOSS" end
    if state then
      if not ApplyStatusIconPackTexture(tex, cfg, status, "elite", state) then
        if tex.SetAtlas then
          SetAtlas(tex, EliteAtlas(state))
        else
          SetTexture(tex, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
          SetTexCoord(tex, 0, 1, 0, 1)
        end
      end
    end
    SetShown(tex, state ~= nil)
  end
  cfg, tex = status.combat, frame.combatStateIndicatorIcon
  if tex then
    local active = cfg and cfg.enabled and sample.combat == true
    if active then ApplyStateOrPackIconTexture(tex, "combat", cfg, status, "combat") end
    SetShown(tex, active and true or false)
  end
  cfg, tex = status.resting, frame.restingIndicatorIcon
  if tex then
    local active = cfg and cfg.enabled and sample.resting == true and frame.MSUFUnitKey == "player"
    if active then
      SetShown(tex, true)
      ApplyStateOrPackIconTexture(tex, "resting", cfg, status, "resting", true)
    else
      StopRestingFlipbook(tex)
      SetShown(tex, false)
    end
  end
  tex, cfg = frame.incomingResIndicatorIcon, status.incomingRes
  local resurrect = sample.incomingRes == true and cfg and cfg.enabled
  if resurrect then ApplyStateOrPackIconTexture(tex, "incomingRes", cfg, status, "resurrect") end
  SetShown(tex, resurrect and true or false)
  cfg, tex = status.pvp, frame.pvpIndicatorIcon
  if tex then
    local faction = cfg and cfg.enabled and sample.pvp or nil
    local atlas = faction == "FFA" and Media.PVP_FFA_ATLAS or faction and PVPAtlasForFaction(faction) or nil
    local shown = false
    if atlas then
      shown = ApplyStatusIconPackTexture(tex, cfg, status, "pvp", PVPVariantForAtlas(atlas)) or ApplyPVPTexture(tex, atlas)
    end
    SetShown(tex, shown and true or false)
  end
  cfg, tex = status.raidGroup, frame.raidGroupNameText
  if tex then
    local subgroup = cfg and cfg.enabled and playerSample and sample.raidGroup or nil
    if subgroup then SetText(tex, Runtime.RaidGroupText(cfg.style, subgroup)) end
    SetShown(tex, subgroup ~= nil)
  end
  local statusText = frame.statusIndicatorText
  if statusText then ClearStatusText(frame, statusText) end
end

local SCENE_STATUS_TEXTS = {
  { "statusText", "dead", "showDead", "DEAD" }, { "statusGhostText", "ghost", "showGhost", "GHOST" },
  { "statusAFKText", "afk", "showAFK", "AFK" }, { "statusDNDText", "dnd", "showDND", "DND" },
}
if IS_FOREVER then
  SCENE_STATUS_TEXTS[#SCENE_STATUS_TEXTS + 1] = { "statusConsumptionText", "consumption", "showConsumption", "DRINKING" }
end
local SCENE_STATUS_FIELDS = {
  { "raidmarker", "raidTargetIcon" },
  { "leader", "leaderIcon" },
  { "assist", "assistIcon" },
  { "level", "levelText" },
  { "bossNumber", "bossNumberText" },
  { "raceText", "raceText" },
  { "classText", "classStatusText" },
  { "elite", "eliteIcon" },
  { "statusCombat", "combatStateIndicatorIcon" },
  { "statusResting", "restingIndicatorIcon" },
  { "statusIncomingRes", "incomingResIndicatorIcon" },
  { "statusPvp", "pvpIndicatorIcon" },
  { "statusPetHappiness", "petHappinessIndicatorHolder" },
  { "statusPetXP", "petXPBar" },
  { "statusThreat", "threatIndicatorHolder" },
  { "stance", "stanceIndicatorText" },
}
-- Options selects one configured indicator or all of them. Extra state texts use the live layout and font rules;
-- there is no unit event, AFK timer or ledger behind these stand-ins.
function Runtime.PaintSceneStatus(frame, status, selection, sample)
  for i = 1, #SCENE_STATUS_FIELDS do
    local key, field = SCENE_STATUS_FIELDS[i][1], SCENE_STATUS_FIELDS[i][2]
    if selection ~= "all" and key ~= selection then SetShown(frame[field], false) end
  end
  local cfg = status.statusText
  for i = 1, #SCENE_STATUS_TEXTS do
    local row = SCENE_STATUS_TEXTS[i]
    local field = "_msufScene_" .. row[1]
    local layout = cfg and (cfg[row[2]] or cfg)
    local shown = cfg and cfg.enabled and cfg[row[3]] and layout.enabled ~= false
      and (selection == "all" or selection == row[1])
    local fs = frame[field]
    if shown then
      fs = fs or EnsureText(frame, field, layout.layer)
      AdoptRegion(frame, fs, layout.layer)
      LayoutRegion(fs, frame, frame.MSUFSpec, layout, true)
      SetText(fs, MSUF.Translate(row[4]))
      fs:SetAlpha((fs._msufStatusAlpha or 1) * (frame._msufAlphaLastFG or 1))
    end
    SetShown(fs, shown and true or false)
  end
  local held = status.testMode
  status.testMode = true
  UpdateAFKTimerText(frame, status, cfg, (selection == "all" or selection == "statusAFKTimer") and "afk" or nil)
  status.testMode = held
  local stance = status.stance
  if stance and stance.enabled and (selection == "all" or selection == "stance") then
    local fs = frame.stanceIndicatorText
    if fs then
      LayoutRegion(fs, frame, frame.MSUFSpec, stance, true)
      SetText(fs, sample and sample.stance or MSUF.Translate("Stance"))
      SetShown(fs, true)
    end
  end
end

-- Asset fields consumed by Config.Status.CompileUnit; deliberately absent style keys stay absent.
-- This read-only projection avoids the full compiler's PvP context and difficulty-palette writes.
local SAMPLE_UNIT_CONFIG = {
  leader = { prefix = "leaderIcon", style = "leaderIconStyle" },
  assist = { prefix = "assistIcon", style = "assistIconStyle" },
  raidMarker = { prefix = "raidMarker" },
  elite = { prefix = "eliteIcon" },
  combat = { prefix = "combatStateIndicator", symbol = "combatStateIndicatorSymbol", defaultSymbol = "DEFAULT" },
  resting = { prefix = "restedStateIndicator", style = "restedStateIndicatorIconStyle", symbol = "restedStateIndicatorSymbol",
    defaultSymbol = "rested_blizzard_animated", legacySymbol = "restingStateIndicatorSymbol" },
  incomingRes = { prefix = "incomingResIndicator", symbol = "incomingResIndicatorSymbol", defaultSymbol = "DEFAULT" },
  pvp = { prefix = "pvpIndicator" },
}
local function SampleString(conf, general, key, fallback, legacy)
  local value = conf[key]
  if type(value) == "string" and value ~= "" then return value end
  value = legacy and conf[legacy]
  if type(value) == "string" and value ~= "" then return value end
  value = general[key]
  if type(value) == "string" and value ~= "" then return value end
  value = legacy and general[legacy]
  if type(value) == "string" and value ~= "" then return value end
  return fallback
end
-- Only caller-owned output tables change; saved settings and live runtime state are read-only.
function Runtime.ResolveUnitIconSampleConfig(cfg, status, conf, general, kind)
  local def = SAMPLE_UNIT_CONFIG[kind]
  cfg.style = def and def.style and SampleString(conf, general, def.style, "BLIZZARD") or nil
  cfg.symbol = def and def.symbol and SampleString(conf, general, def.symbol, def.defaultSymbol, def.legacySymbol) or nil
  cfg.customIcon = def and SampleString(conf, general, def.prefix .. "CustomIcon", "") or nil
  local midnight = conf.statusIconsUseMidnightStyle
  if midnight == nil then midnight = general.statusIconsUseMidnightStyle end
  status.useMidnight = UF.BoolWithFallback(midnight, false)
end

-- Cold sample adapters take scalar configuration and paint only the supplied sample region.
-- They reuse the live painters and asset helpers; no live updater calls this dispatch.
local function SampleLeader(tex, cfg, status)
  ApplyLeaderTexture(tex, cfg, status, false)
  return true
end
local function SampleAssist(tex, cfg, status)
  ApplyLeaderTexture(tex, cfg, status, true)
  return true
end
local function SampleState(tex, cfg, status, variant, kind)
  return ApplyStateOrPackIconTexture(tex, kind, cfg, status, variant, true)
end
local function SampleRaidMarker(tex, cfg, status, index)
  if not ApplyStatusIconPackTexture(tex, cfg, status, "raidMarker", index) then
    ApplyDefaultRaidMarkerTexture(tex, index)
  end
  return true
end
local function SampleElite(tex, cfg, status, state)
  if not ApplyStatusIconPackTexture(tex, cfg, status, "elite", state) then
    if tex.SetAtlas then
      SetAtlas(tex, EliteAtlas(state))
    else
      SetTexture(tex, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
      SetTexCoord(tex, 0, 1, 0, 1)
    end
  end
  return true
end
local function SamplePVP(tex, cfg, status, faction)
  local atlas = faction == "FFA" and Media.PVP_FFA_ATLAS or PVPAtlasForFaction(faction)
  return ApplyStatusIconPackTexture(tex, cfg, status, "pvp", faction) or ApplyPVPTexture(tex, atlas)
end
local function SampleGroupIcon(tex, cfg, status, variant, kind)
  if ApplyStatusIconPackTexture(tex, cfg, status, kind, variant) then return true end
  local path = kind == "readyCheck" and Media.READY_TEXTURES[variant]
    or kind == "summon" and SUMMON_TEXTURES[variant] or kind == "phase" and Media.PHASE_TEXTURE
  if not path then return false end
  SetTexture(tex, path)
  SetTexCoord(tex, 0, 1, 0, 1)
  return true
end
local function SamplePetHappiness(tex, cfg, status, happiness)
  local resolver = MSUF.Optional("MSUF_GetPetHappinessIcon")
  if not resolver then return false end
  local path, l, r, t, b, atlas = resolver(happiness)
  if atlas and tex.SetAtlas then
    SetAtlas(tex, atlas)
  elseif path then
    SetTexture(tex, path)
    SetTexCoord(tex, l, r, t, b)
  else
    return false
  end
  return true
end
local SAMPLE_PAINTERS = {
  leader = SampleLeader, assist = SampleAssist, role = ApplyRoleTexture,
  combat = SampleState, resting = SampleState, incomingRes = SampleState,
  raidMarker = SampleRaidMarker, elite = SampleElite, pvp = SamplePVP,
  readyCheck = SampleGroupIcon, summon = SampleGroupIcon, phase = SampleGroupIcon,
  petHappiness = SamplePetHappiness,
}
-- Pure resolver: stable runtime-owned output functions, no unit/profile reads or writes.
function Runtime.ResolveIconSample(kind)
  return SAMPLE_PAINTERS[kind]
end
function Runtime.PaintIconSample(tex, cfg, status, kind, variant)
  local painter = Runtime.ResolveIconSample(kind)
  if not (tex and painter) then return false end
  return painter(tex, cfg, status, variant, kind)
end

local function BindStatusIndicatorArt(values)
  ApplyDefaultRaidMarkerTexture = values.ApplyDefaultRaidMarkerTexture
end

return ApplyRoleTexture, ApplyStateOrPackIconTexture, ApplyStatusIconPackTexture, HideAFKTimerText, BindStatusIndicatorArt
end
