-- UF responsibility owner; dependencies bind once before runtime.
local _, MSUF = ...
MSUF.UFModuleFactories = MSUF.UFModuleFactories or {}

MSUF.UFModuleFactories.StatusLevelBadge = function(
  BoolTrue, FreshUnitState, HideField, ReadUnitClassCached, Runtime, SafeNumber, SetShown, SetText, UnitExistsRuntime, UnitLevel, UnitRace,
    issecretvalue, tostring, type
)

function Runtime.SetForeverLevelBadgeShown(frame, shown)
  local badge = frame and frame.levelBackdrop
  SetShown(badge, badge ~= nil and shown == true)
  local ring = frame and frame.levelBackdropRing
  SetShown(ring, ring ~= nil and shown == true)
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

local IDENTITY_TEXT_FIELDS = { "levelText", "levelBackdrop", "levelBackdropRing", "raceText", "classStatusText" }

--- Level difficulty tier, mirroring TargetFrameMixin:CheckLevel. Returns an
--- index into Shared.LEVEL_DIFFICULTY_TIERS. Hung on Runtime, like the other
--- cold helpers here.
function Runtime.BuildLevelTierMap()
  local map = {}
  local difficulty = _G.Enum and _G.Enum.RelativeContentDifficulty
  if difficulty then
    if difficulty.Impossible ~= nil then map[difficulty.Impossible] = 1 end
    if difficulty.Difficult ~= nil then map[difficulty.Difficult] = 2 end
    if difficulty.Fair ~= nil then map[difficulty.Fair] = 3 end
    if difficulty.Easy ~= nil then map[difficulty.Easy] = 4 end
    if difficulty.Trivial ~= nil then map[difficulty.Trivial] = 5 end
  end
  Runtime.levelTierByDifficulty = map
  return map
end

function Runtime.LevelDifficultyTier(unit, level)
  -- "??" is always the top band, attackable or not.
  if level == -1 then return 1 end
  -- Blizzard only grades what the player can attack; everything else keeps the
  -- standard color.
  local canAttack = _G.UnitCanAttack
  if not (canAttack and BoolTrue(canAttack("player", unit))) then return 3 end
  local playerInfo = _G.C_PlayerInfo
  local getDifficulty = playerInfo and playerInfo.GetContentDifficultyCreatureForPlayer
  if getDifficulty then
    -- Server-side grading: correct under level scaling and Timewalking, where
    -- a raw level gap is not.
    local difficulty = getDifficulty(unit)
    if issecretvalue(difficulty) ~= true then
      local tier = (Runtime.levelTierByDifficulty or Runtime.BuildLevelTierMap())[difficulty]
      if tier then return tier end
    end
    return 3
  end
  -- Clients without that API (Classic flavors) use GetRelativeDifficultyColor's
  -- level-gap bands.
  local readPlayerLevel = _G.UnitEffectiveLevel or UnitLevel
  local playerLevel = readPlayerLevel and SafeNumber(readPlayerLevel("player"))
  if not (level and playerLevel) then return 3 end
  local diff = level - playerLevel
  if diff >= 5 then return 1 end
  if diff >= 3 then return 2 end
  if diff >= -2 then return 3 end
  local greenRange = _G.GetQuestGreenRange and SafeNumber(_G.GetQuestGreenRange()) or 8
  if -diff <= greenRange then return 4 end
  return 5
end

--- `tier` pins the band for previews, which have no real unit to grade.
function Runtime.ApplyLevelDifficultyColor(region, frame, unit, level, cfg, tier)
  local colors = cfg.difficultyColors
  if not (region and colors and region.SetTextColor) then return end
  tier = tier or Runtime.LevelDifficultyTier(unit, level)
  region._msufLevelTier = tier
  local base = (tier - 1) * 3
  local r, g, b = colors[base + 1], colors[base + 2], colors[base + 3]
  -- Alpha stays with the frame's shared font text alpha, as in ApplyTextColor.
  local spec = frame.MSUFSpec
  local c = spec and spec.textColor
  local a = c and c.a or 1
  if region._msufStatusR ~= r or region._msufStatusG ~= g or region._msufStatusB ~= b or region._msufStatusA ~= a then
    region:SetTextColor(r, g, b, a)
    region._msufStatusR, region._msufStatusG, region._msufStatusB, region._msufStatusA = r, g, b, a
  end
end

function Runtime.UpdateIdentityTexts(frame, status)
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
      if levelCfg.difficultyColor == true then
        Runtime.ApplyLevelDifficultyColor(frame.levelText, frame, unit, level, levelCfg)
      end
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
  Runtime.SetForeverLevelBadgeShown(frame, showLevel and levelPresent and levelCfg.foreverBadge == true)
  if showRace then ShowIdentityText(frame.raceText, raceText, racePresent) else SetShown(frame.raceText, false) end
  if showClass then ShowIdentityText(frame.classStatusText, classText, classPresent) else SetShown(frame.classStatusText, false) end
end

--- Is the identity text `field` switched on in `cfg` and built on the frame?
local function IdentityWanted(frame, cfg, field)
  return cfg and cfg.enabled == true and frame[field] ~= nil
end

--- Scene form of UpdateIdentityTexts: the sample's level (graded by its tier), race and class texts.
function Runtime.PaintSampleIdentityTexts(frame, status, sample)
  local levelCfg = status and status.level
  local showLevel = IdentityWanted(frame, levelCfg, "levelText")
  local showRace = IdentityWanted(frame, status and status.race, "raceText")
  local showClass = IdentityWanted(frame, status and status.classText, "classStatusText")
  if not (showLevel or showRace or showClass) then
    HideField(frame, IDENTITY_TEXT_FIELDS)
    return
  end
  local level = showLevel and tonumber(sample.level) or nil
  if level then
    SetText(frame.levelText, level == -1 and "??" or tostring(level))
    if levelCfg.difficultyColor == true then
      Runtime.ApplyLevelDifficultyColor(frame.levelText, frame, nil, nil, levelCfg, level == -1 and 1 or sample.levelTier or 3)
    end
  end
  SetShown(frame.levelText, level ~= nil)
  Runtime.SetForeverLevelBadgeShown(frame, level ~= nil and levelCfg.foreverBadge == true)
  local race = showRace and sample.race or nil
  if race then SetText(frame.raceText, race) end
  SetShown(frame.raceText, race ~= nil)
  local className = showClass and sample.className or nil
  if className then SetText(frame.classStatusText, className) end
  SetShown(frame.classStatusText, className ~= nil)
end

local function BindStatusLevelBadge(values)
  HideField = values.HideField
end

return BindStatusLevelBadge
end
