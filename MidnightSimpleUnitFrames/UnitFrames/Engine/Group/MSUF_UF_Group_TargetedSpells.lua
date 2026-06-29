--- UnitFrames/Engine/Group/MSUF_UF_Group_TargetedSpells.lua
--- Party-only targeted spell indicators.
---
--- Watches enemy nameplate casts, resolves a single targeted party member from
--- exposed target metadata, then shows the cast icon on that party frame.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF

local TS = GF.TargetedSpells or {}
GF.TargetedSpells = TS

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local C_NamePlate = C_NamePlate
local GetSpecialization = GetSpecialization
local GetSpecializationRole = GetSpecializationRole
local GetTime = GetTime
local IsInGroup = IsInGroup
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local UnitCanAttack = UnitCanAttack
local UnitCastingInfo = UnitCastingInfo
local UnitCastingDuration = _G.UnitCastingDuration
local UnitChannelInfo = UnitChannelInfo
local UnitChannelDuration = _G.UnitChannelDuration
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitRace = UnitRace
local UnitSex = UnitSex
local UnitShouldDisplaySpellTargetName = UnitShouldDisplaySpellTargetName
local ceil = math.ceil
local floor = math.floor
local max = math.max
local pairs = pairs
local pcall = pcall
local string_format = string.format
local tremove = table.remove
local type = type
local wipe = wipe or function(t)
  for k in pairs(t) do
    t[k] = nil
  end
  return t
end
local issecretvalue = _G.issecretvalue or function(_) return false end

local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local PICKUP_DELAY = 0.10
local VERIFY_DELAY = 0.15
local RETARGET_DELAY = 0.05
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local HOT_EVENTS = {
  "NAME_PLATE_UNIT_ADDED",
  "NAME_PLATE_UNIT_REMOVED",
  "UNIT_TARGET",
  "UNIT_SPELLCAST_START",
  "UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_STOP",
  "UNIT_SPELLCAST_CHANNEL_STOP",
  "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_FAILED",
}

local CONTROL_EVENTS = {
  "GROUP_ROSTER_UPDATE",
  "PLAYER_ROLES_ASSIGNED",
  "PLAYER_SPECIALIZATION_CHANGED",
  "ROLE_CHANGED_INFORM",
}

local ANCHORS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true,
  LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local GROWS = { CENTER = true, RIGHT = true, LEFT = true, UP = true, DOWN = true }

local settings = {
  enabled = false,
  mode = "whenHealing",
  size = 24,
  maxIcons = 3,
  anchor = "CENTER",
  grow = "CENTER",
  x = 0,
  y = 0,
  layer = 10,
  textEnabled = true,
  textSize = 10,
  textDecimalBelow = 3,
  textColorByTime = false,
  textSafeSeconds = 60,
  textWarningSeconds = 15,
  textUrgentSeconds = 5,
  textSafeR = 1,
  textSafeG = 1,
  textSafeB = 1,
  textWarningR = 1,
  textWarningG = 0.85,
  textWarningB = 0.20,
  textUrgentR = 1,
  textUrgentG = 0.55,
  textUrgentB = 0.10,
}

local eventFrame = CreateFrame("Frame")
local hotRegistered = false
local controlRegistered = false
local active = false
local hooksInstalled = false

local nameplateUnits = {}
local trackedCasters = {}
local casterGeneration = {}
local activeByCaster = {}
local frameIcons = setmetatable({}, { __mode = "k" })
local activeTextIcons = setmetatable({}, { __mode = "k" })
local activeTextCount = 0
local textTicker

local rosterByClass = {}
local rosterRole = {}
local rosterRace = {}
local rosterSex = {}
local matchBuf = {}
local clearBuf = {}
local lastRosterSync = 0

local function IsSecret(value)
  return issecretvalue(value) == true
end

local function PlainNumber(value)
  if value == nil then return nil end

  local runtimePlain = _G.MSUF_CastbarRuntime_PlainNumber
  if type(runtimePlain) == "function" then
    local plain = runtimePlain(value)
    if IsSecret(plain) ~= true then
      local number = tonumber(tostring(plain))
      if number ~= nil then return number end
    end
    return nil
  end

  local toPlain = _G.ToPlain
  if type(toPlain) == "function" then
    local plain = toPlain(value)
    if IsSecret(plain) ~= true then
      local number = tonumber(tostring(plain))
      if number ~= nil then return number end
    end
  end

  if IsSecret(value) == true then return nil end
  local valueType = type(value)
  if valueType == "number" or valueType == "string" then
    return tonumber(tostring(value))
  end
  return nil
end

local function IsUnitToken(unit)
  return IsSecret(unit) ~= true and type(unit) == "string" and unit ~= ""
end

local function Conf()
  if GF.GetConf then
    return GF.GetConf("party")
  end
  local db = _G.MSUF_DB
  return db and db.gf_party
end

local function ReadValue(key, fallback)
  local conf = Conf()
  local value = conf and conf[key]
  if value == nil then
    return fallback
  end
  return value
end

local function ClampInt(value, fallback, minValue, maxValue)
  value = floor((tonumber(value) or fallback or 0) + 0.5)
  if minValue and value < minValue then return minValue end
  if maxValue and value > maxValue then return maxValue end
  return value
end

local function ClampNumber(value, fallback, minValue, maxValue)
  value = tonumber(value)
  if value == nil then value = fallback or 0 end
  if minValue and value < minValue then return minValue end
  if maxValue and value > maxValue then return maxValue end
  return value
end

local function Clamp01(value, fallback)
  return ClampNumber(value, fallback or 1, 0, 1)
end

local function NormalizeKey(value, allowed, fallback)
  if type(value) ~= "string" then return fallback end
  value = value:upper()
  return allowed[value] and value or fallback
end

local function ReadSettings()
  settings.enabled = ReadValue("targetedSpellsEnabled", false) == true
  settings.mode = ReadValue("targetedSpellsMode", "whenHealing")
  settings.size = ClampInt(ReadValue("targetedSpellsIconSize", 24), 24, 8, 64)
  settings.maxIcons = ClampInt(ReadValue("targetedSpellsMaxIcons", 3), 3, 1, 5)
  settings.anchor = NormalizeKey(ReadValue("targetedSpellsAnchor", "CENTER"), ANCHORS, "CENTER")
  settings.grow = NormalizeKey(ReadValue("targetedSpellsGrow", "CENTER"), GROWS, "CENTER")
  settings.x = ClampInt(ReadValue("targetedSpellsX", 0), 0, -200, 200)
  settings.y = ClampInt(ReadValue("targetedSpellsY", 0), 0, -200, 200)
  settings.layer = ClampInt(ReadValue("targetedSpellsLayer", 10), 10, 0, 30)
  settings.textEnabled = ReadValue("targetedSpellsTextEnabled", true) ~= false
  settings.textSize = ClampInt(ReadValue("targetedSpellsTextSize", 10), 10, 6, 24)
  settings.textDecimalBelow = ClampNumber(ReadValue("targetedSpellsTextDecimalBelow", 3), 3, 0, 30)
  settings.textColorByTime = ReadValue("targetedSpellsTextColorByTime", false) == true
  settings.textUrgentSeconds = ClampNumber(ReadValue("targetedSpellsTextUrgentSeconds", 5), 5, 0, 30)
  settings.textWarningSeconds = ClampNumber(ReadValue("targetedSpellsTextWarningSeconds", 15), 15, 0, 60)
  settings.textSafeSeconds = ClampNumber(ReadValue("targetedSpellsTextSafeSeconds", 60), 60, 0, 600)
  if settings.textWarningSeconds < settings.textUrgentSeconds then settings.textWarningSeconds = settings.textUrgentSeconds end
  if settings.textSafeSeconds < settings.textWarningSeconds then settings.textSafeSeconds = settings.textWarningSeconds end
  settings.textSafeR = Clamp01(ReadValue("targetedSpellsTextSafeR", 1), 1)
  settings.textSafeG = Clamp01(ReadValue("targetedSpellsTextSafeG", 1), 1)
  settings.textSafeB = Clamp01(ReadValue("targetedSpellsTextSafeB", 1), 1)
  settings.textWarningR = Clamp01(ReadValue("targetedSpellsTextWarningR", 1), 1)
  settings.textWarningG = Clamp01(ReadValue("targetedSpellsTextWarningG", 0.85), 0.85)
  settings.textWarningB = Clamp01(ReadValue("targetedSpellsTextWarningB", 0.20), 0.20)
  settings.textUrgentR = Clamp01(ReadValue("targetedSpellsTextUrgentR", 1), 1)
  settings.textUrgentG = Clamp01(ReadValue("targetedSpellsTextUrgentG", 0.55), 0.55)
  settings.textUrgentB = Clamp01(ReadValue("targetedSpellsTextUrgentB", 0.10), 0.10)
end

local function HasInstancedPartyRoster()
  if IsInRaid and IsInRaid() then return false end
  if IsInGroup and IsInGroup() then return true end

  local inInstance = IsInInstance and IsInInstance()
  if inInstance ~= true then return false end

  for i = 2, #PARTY_UNITS do
    local exists = UnitExists and UnitExists(PARTY_UNITS[i])
    if IsSecret(exists) ~= true and exists == true then
      return true
    end
  end

  local conf = Conf()
  if not (conf and conf.showSolo == true and conf.showPlayer ~= false) then return false end
  local playerExists = UnitExists and UnitExists("player")
  return IsSecret(playerExists) == true or playerExists == true
end

local function InParty()
  if not HasInstancedPartyRoster() then return false end
  return true
end

local function RoleAllows()
  local mode = settings.mode
  if mode == "always" then return true end
  if mode == "never" then return false end
  if mode ~= "whenHealing" then return false end
  if not (GetSpecialization and GetSpecializationRole) then return false end
  local spec = GetSpecialization()
  if not spec then return false end
  return GetSpecializationRole(spec) == "HEALER"
end

local function ShouldRun()
  if settings.enabled ~= true then return false end
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return false end
  return InParty() and RoleAllows()
end

local function SetEvents(events, enable)
  for i = 1, #events do
    if enable then
      eventFrame:RegisterEvent(events[i])
    else
      eventFrame:UnregisterEvent(events[i])
    end
  end
end

local function SetHotEvents(enable)
  enable = enable == true
  if hotRegistered == enable then return end
  hotRegistered = enable
  SetEvents(HOT_EVENTS, enable)
end

local function SetControlEvents(enable)
  enable = enable == true
  if controlRegistered == enable then return end
  controlRegistered = enable
  SetEvents(CONTROL_EVENTS, enable)
end

local function Schedule(delay, fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, fn)
  else
    fn()
  end
end

local function AnchorHost(frame)
  return frame and (frame.hpBar or frame.Health or frame)
end

local function BaseFrameLevel(frame)
  local host = AnchorHost(frame)
  local hostLevel = host and host.GetFrameLevel and (host:GetFrameLevel() or 0) or 0
  local frameLevel = frame and frame.GetFrameLevel and (frame:GetFrameLevel() or 0) or 0
  return max(hostLevel or 0, frameLevel or 0)
end

local function SetShown(frame, shown)
  if not frame then return end
  shown = shown == true
  if frame._msufTSShown == shown then return end
  frame:SetShown(shown)
  frame._msufTSShown = shown
end

local function SetPointCached(region, point, relativeTo, relativePoint, x, y)
  x, y = x or 0, y or 0
  relativePoint = relativePoint or point
  if region._msufTSPoint == point
    and region._msufTSRel == relativeTo
    and region._msufTSRelPoint == relativePoint
    and region._msufTSX == x
    and region._msufTSY == y then
    return
  end
  region._msufTSPoint = point
  region._msufTSRel = relativeTo
  region._msufTSRelPoint = relativePoint
  region._msufTSX = x
  region._msufTSY = y
  region:ClearAllPoints()
  region:SetPoint(point, relativeTo, relativePoint, x, y)
end

local function TextColorForRemaining(remaining)
  if settings.textColorByTime ~= true then
    return 1, 1, 1
  end
  if remaining <= settings.textUrgentSeconds then
    return settings.textUrgentR, settings.textUrgentG, settings.textUrgentB
  elseif remaining <= settings.textWarningSeconds then
    return settings.textWarningR, settings.textWarningG, settings.textWarningB
  elseif remaining <= settings.textSafeSeconds then
    return settings.textSafeR, settings.textSafeG, settings.textSafeB
  end
  return 1, 1, 1
end

local function FormatRemaining(remaining)
  remaining = max(0, tonumber(remaining) or 0)
  if settings.textDecimalBelow > 0 and remaining < settings.textDecimalBelow then
    return string_format("%.1f", remaining)
  end
  return tostring(ceil(remaining))
end

local function EnsureIconText(icon)
  if not icon then return nil end
  if icon.text then return icon.text end
  local parent = icon.textLayer or icon
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("CENTER", parent, "CENTER", 0, 0)
  fs:SetJustifyH("CENTER")
  if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
  fs:Hide()
  icon.text = fs
  return fs
end

local function ApplyIconTextStyle(icon)
  local fs = EnsureIconText(icon)
  if not fs then return end
  local size = settings.textSize
  if icon._msufTSTextSize ~= size then
    fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    icon._msufTSTextSize = size
  end
end

local function StopTextTicker()
  if textTicker and textTicker.Cancel then
    textTicker:Cancel()
  end
  textTicker = nil
end

local function ReleaseTextIcon(icon)
  if not icon then return end
  if icon._msufTSTextActive then
    activeTextIcons[icon] = nil
    activeTextCount = max(0, activeTextCount - 1)
    icon._msufTSTextActive = nil
  end
  icon._msufTSEndTime = nil
  if icon.text then
    icon.text:SetText("")
    icon.text:Hide()
  end
  if activeTextCount <= 0 then
    StopTextTicker()
  end
end

local function UpdateIconText(icon, now)
  if not (icon and settings.textEnabled == true and icon._msufTSEndTime) then
    if icon and icon.text then
      icon.text:SetText("")
      icon.text:Hide()
    end
    return false
  end
  now = now or (GetTime and GetTime()) or 0
  local remaining = (tonumber(icon._msufTSEndTime) or 0) - now
  if remaining <= 0 then
    if icon.text then
      icon.text:SetText("")
      icon.text:Hide()
    end
    return false
  end
  ApplyIconTextStyle(icon)
  local fs = icon.text
  if not fs then return false end
  fs:SetText(FormatRemaining(remaining))
  local r, g, b = TextColorForRemaining(remaining)
  fs:SetTextColor(r or 1, g or 1, b or 1, 1)
  fs:Show()
  return true
end

local function TextTickerPulse()
  local now = (GetTime and GetTime()) or 0
  for icon in pairs(activeTextIcons) do
    if not UpdateIconText(icon, now) then
      ReleaseTextIcon(icon)
    end
  end
  if activeTextCount <= 0 then
    StopTextTicker()
  end
end

local function StartTextTicker()
  if textTicker or activeTextCount <= 0 then return end
  if C_Timer and C_Timer.NewTicker then
    textTicker = C_Timer.NewTicker(settings.textDecimalBelow > 0 and 0.10 or 0.25, TextTickerPulse)
  end
end

local function ActivateTextIcon(icon)
  if not icon then return end
  if icon._msufTSTextActive ~= true then
    activeTextIcons[icon] = true
    activeTextCount = activeTextCount + 1
    icon._msufTSTextActive = true
  end
  UpdateIconText(icon)
  StartTextTicker()
end

local function SetIconTiming(icon, durationObj, startMS, endMS)
  if not icon then return end
  if settings.textEnabled ~= true then
    ReleaseTextIcon(icon)
    return
  end

  local remaining
  if durationObj then
    if durationObj.GetRemainingDuration then
      remaining = PlainNumber(durationObj:GetRemainingDuration())
    elseif durationObj.GetRemaining then
      remaining = PlainNumber(durationObj:GetRemaining())
    end
  end
  if remaining and remaining > 0 then
    icon._msufTSEndTime = ((GetTime and GetTime()) or 0) + remaining
    ActivateTextIcon(icon)
    return
  end

  startMS = PlainNumber(startMS)
  endMS = PlainNumber(endMS)
  if settings.textEnabled == true and startMS and endMS and endMS > startMS then
    icon._msufTSEndTime = endMS * 0.001
    ActivateTextIcon(icon)
  else
    ReleaseTextIcon(icon)
  end
end

local function ApplyIconFrame(icon, frame)
  if not icon then return end
  local holder = frame and frame.MSUFGFTargetedSpellsHolder
  if not holder then
    holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    holder:EnableMouse(false)
    frame.MSUFGFTargetedSpellsHolder = holder
  end
  if holder.SetFrameStrata and frame.GetFrameStrata then
    holder:SetFrameStrata(frame:GetFrameStrata())
  end
  local holderLevel = BaseFrameLevel(frame) + 40 + settings.layer
  if holder.SetFrameLevel and holder._msufTSLevel ~= holderLevel then
    holder:SetFrameLevel(holderLevel)
    holder._msufTSLevel = holderLevel
  end
  if icon.GetParent and icon:GetParent() ~= holder then
    icon:SetParent(holder)
  end
  local size = settings.size
  if icon._msufTSSize ~= size then
    icon:SetSize(size, size)
    icon._msufTSSize = size
  end
  local level = holderLevel + 1
  if icon.SetFrameLevel and icon._msufTSLevel ~= level then
    icon:SetFrameLevel(level)
    icon._msufTSLevel = level
  end
  if icon.cooldown and icon.cooldown.SetFrameLevel then
    icon.cooldown:SetFrameLevel(level + 1)
  end
  if icon.textLayer then
    icon.textLayer:ClearAllPoints()
    icon.textLayer:SetAllPoints(icon)
    if icon.textLayer.SetFrameLevel then icon.textLayer:SetFrameLevel(level + 3) end
  end
  if settings.textEnabled == true or icon.text then
    ApplyIconTextStyle(icon)
  end
end

local function LayoutFrame(frame)
  local icons = frame and frameIcons[frame]
  if not icons then return end
  local host = AnchorHost(frame)
  if not host then return end

  local shown = 0
  for i = 1, #icons do
    if icons[i]._msufTSCaster then
      shown = shown + 1
    end
  end
  if shown == 0 then return end

  local size = settings.size
  local gap = 2
  local spacing = size + gap
  local grow = settings.grow
  local firstX = settings.x
  local firstY = settings.y
  if grow == "CENTER" and shown > 1 then
    firstX = firstX - ((shown - 1) * spacing * 0.5)
  end

  local previous
  for i = 1, #icons do
    local icon = icons[i]
    if icon._msufTSCaster then
      ApplyIconFrame(icon, frame)
      if not previous then
        SetPointCached(icon, settings.anchor, host, settings.anchor, firstX, firstY)
      elseif grow == "LEFT" then
        SetPointCached(icon, "RIGHT", previous, "LEFT", -gap, 0)
      elseif grow == "UP" then
        SetPointCached(icon, "BOTTOM", previous, "TOP", 0, gap)
      elseif grow == "DOWN" then
        SetPointCached(icon, "TOP", previous, "BOTTOM", 0, -gap)
      else
        SetPointCached(icon, "LEFT", previous, "RIGHT", gap, 0)
      end
      previous = icon
    end
  end
end

local function CreateIcon(frame)
  local holder = frame.MSUFGFTargetedSpellsHolder
  if not holder then
    holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    holder:EnableMouse(false)
    frame.MSUFGFTargetedSpellsHolder = holder
  end
  local icon = CreateFrame("Frame", nil, holder)
  icon:EnableMouse(false)

  local tex = icon:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints(icon)
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon.tex = tex

  local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
  cooldown:SetAllPoints(icon)
  if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
  if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(true) end
  if cooldown.SetSwipeColor then cooldown:SetSwipeColor(0, 0, 0, 0.58) end
  if cooldown.SetReverse then cooldown:SetReverse(true) end
  if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
  cooldown:Hide()
  icon.cooldown = cooldown

  local textLayer = CreateFrame("Frame", nil, icon)
  textLayer:SetAllPoints(icon)
  textLayer:EnableMouse(false)
  icon.textLayer = textLayer

  ApplyIconFrame(icon, frame)
  icon:Hide()
  return icon
end

local function ActiveIconCount(frame)
  local icons = frame and frameIcons[frame]
  if not icons then return 0 end
  local count = 0
  for i = 1, #icons do
    if icons[i]._msufTSCaster then
      count = count + 1
    end
  end
  return count
end

local function AcquireIcon(frame)
  if ActiveIconCount(frame) >= settings.maxIcons then return nil end
  local icons = frameIcons[frame]
  if not icons then
    icons = {}
    frameIcons[frame] = icons
  end
  for i = 1, #icons do
    if not icons[i]._msufTSCaster then
      return icons[i]
    end
  end
  local icon = CreateIcon(frame)
  icons[#icons + 1] = icon
  return icon
end

local function ApplyCooldown(cooldown, durationObj, startMS, endMS)
  if not cooldown then return end
  if durationObj and cooldown.SetCooldownFromDurationObject then
    cooldown:SetCooldownFromDurationObject(durationObj)
    if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(true) end
    cooldown:Show()
    return
  end

  startMS = PlainNumber(startMS)
  endMS = PlainNumber(endMS)
  if startMS and endMS and endMS > startMS and cooldown.SetCooldown then
    cooldown:SetCooldown(startMS * 0.001, (endMS - startMS) * 0.001)
    if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(true) end
    cooldown:Show()
    return
  end

  if cooldown.Clear then
    cooldown:Clear()
  elseif cooldown.SetCooldown then
    cooldown:SetCooldown(0, 0)
  end
  cooldown:Hide()
end

local function HideCasterIcon(caster)
  local rec = caster and activeByCaster[caster]
  if not rec then return end
  activeByCaster[caster] = nil
  local icon = rec.icon
  if icon then
    icon._msufTSCaster = nil
    ReleaseTextIcon(icon)
    SetShown(icon, false)
    ApplyCooldown(icon.cooldown)
  end
  LayoutFrame(rec.frame)
end

local function ClearCaster(caster)
  if not caster then return end
  casterGeneration[caster] = (casterGeneration[caster] or 0) + 1
  trackedCasters[caster] = nil
  HideCasterIcon(caster)
end

local function ClearAll()
  wipe(clearBuf)
  for caster in pairs(activeByCaster) do
    clearBuf[#clearBuf + 1] = caster
  end
  for i = 1, #clearBuf do
    ClearCaster(clearBuf[i])
    clearBuf[i] = nil
  end
  for caster in pairs(trackedCasters) do
    casterGeneration[caster] = (casterGeneration[caster] or 0) + 1
  end
  wipe(trackedCasters)
end

local function RefreshVisibleIcons()
  for frame, icons in pairs(frameIcons) do
    if frame and icons then
      for i = 1, #icons do
        if icons[i]._msufTSCaster then
          ApplyIconFrame(icons[i], frame)
          if settings.textEnabled == true then
            UpdateIconText(icons[i])
          else
            ReleaseTextIcon(icons[i])
          end
        end
      end
      LayoutFrame(frame)
    end
  end
end

local function FrameForPartyUnit(unit)
  if not IsUnitToken(unit) then return nil end
  local frame = GF.FrameForUnit and GF.FrameForUnit(unit)
  if frame and frame._msufGFKind == "party" and (not frame.IsShown or frame:IsShown()) then
    return frame
  end

  if not (GF.ForEachFrame and UnitGUID) then return nil end
  local targetGUID = UnitGUID(unit)
  if IsSecret(targetGUID) == true or targetGUID == nil then return nil end

  local matched
  GF.ForEachFrame(function(candidate, frameUnit, kind)
    if matched or kind ~= "party" or not candidate then return end
    if candidate.IsShown and not candidate:IsShown() then return end
    frameUnit = IsUnitToken(frameUnit) and frameUnit or candidate.unit
    if not IsUnitToken(frameUnit) then return end
    local frameGUID = UnitGUID(frameUnit)
    if IsSecret(frameGUID) ~= true and frameGUID == targetGUID then
      matched = candidate
      return true
    end
  end, true)
  return matched
end

local function FirstPartyFrame()
  if not GF.ForEachFrame then return nil end
  local matched
  GF.ForEachFrame(function(candidate, _, kind)
    if matched or kind ~= "party" or not candidate then return end
    if candidate.IsShown and not candidate:IsShown() then return end
    matched = candidate
    return true
  end, true)
  return matched
end

local function ShowFor(caster, unit, cast)
  local frame = FrameForPartyUnit(unit)
  if not frame then
    HideCasterIcon(caster)
    return
  end

  local rec = activeByCaster[caster]
  if rec and rec.unit == unit and rec.frame == frame then
    if rec.icon and rec.icon.tex then
      rec.icon.tex:SetTexture(cast.texture or FALLBACK_ICON)
      ApplyCooldown(rec.icon.cooldown, cast.durationObj, cast.startMS, cast.endMS)
      SetIconTiming(rec.icon, cast.durationObj, cast.startMS, cast.endMS)
    end
    return
  end

  if rec then
    HideCasterIcon(caster)
  end

  local icon = AcquireIcon(frame)
  if not icon then return end
  icon._msufTSCaster = caster
  icon.tex:SetTexture(cast.texture or FALLBACK_ICON)
  ApplyIconFrame(icon, frame)
  ApplyCooldown(icon.cooldown, cast.durationObj, cast.startMS, cast.endMS)
  SetIconTiming(icon, cast.durationObj, cast.startMS, cast.endMS)
  SetShown(icon, true)
  activeByCaster[caster] = { icon = icon, frame = frame, unit = unit }
  LayoutFrame(frame)
end

local function RebuildRoster()
  for _, list in pairs(rosterByClass) do
    wipe(list)
  end
  wipe(rosterRole)
  wipe(rosterRace)
  wipe(rosterSex)

  for i = 1, #PARTY_UNITS do
    local unit = PARTY_UNITS[i]
    local exists = UnitExists and UnitExists(unit)
    if exists == true and IsSecret(exists) ~= true then
      local _, classToken = UnitClass(unit)
      if IsSecret(classToken) ~= true and type(classToken) == "string" then
        local list = rosterByClass[classToken]
        if not list then
          list = {}
          rosterByClass[classToken] = list
        end
        list[#list + 1] = unit
      end

      local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
      if IsSecret(role) ~= true and type(role) == "string" and role ~= "NONE" then
        rosterRole[unit] = role
      end

      if UnitRace then
        local _, raceToken = UnitRace(unit)
        if IsSecret(raceToken) ~= true and type(raceToken) == "string" then
          rosterRace[unit] = raceToken
        end
      end

      if UnitSex then
        local sex = UnitSex(unit)
        if IsSecret(sex) ~= true and type(sex) == "number" then
          rosterSex[unit] = sex
        end
      end
    end
  end

  lastRosterSync = GetTime and GetTime() or 0
end

local function CopyClassCandidates(classToken)
  wipe(matchBuf)
  local list = rosterByClass[classToken]
  if not list or #list == 0 then return false end
  for i = 1, #list do
    matchBuf[i] = list[i]
  end
  return true
end

local function NarrowCandidates(targetValue, rosterMap)
  if targetValue == nil or #matchBuf <= 1 then return end
  local exact = 0
  for i = 1, #matchBuf do
    if rosterMap[matchBuf[i]] == targetValue then
      exact = exact + 1
    end
  end
  if exact == 0 then return end
  for i = #matchBuf, 1, -1 do
    if rosterMap[matchBuf[i]] ~= targetValue then
      tremove(matchBuf, i)
    end
  end
end

local function SafeTargetRace(unit)
  if not UnitRace then return nil end
  local ok, _, raceToken = pcall(UnitRace, unit)
  if ok and IsSecret(raceToken) ~= true and type(raceToken) == "string" then
    return raceToken
  end
  return nil
end

local function SafeTargetSex(unit)
  if not UnitSex then return nil end
  local ok, sex = pcall(UnitSex, unit)
  if ok and IsSecret(sex) ~= true and type(sex) == "number" then
    return sex
  end
  return nil
end

local function ClassifyTarget(caster)
  local target = caster .. "target"
  local _, classToken = UnitClass(target)
  if IsSecret(classToken) == true or type(classToken) ~= "string" then return nil end

  if not CopyClassCandidates(classToken) then
    local now = GetTime and GetTime() or 0
    if now - lastRosterSync > 1 then
      RebuildRoster()
      CopyClassCandidates(classToken)
    end
  end
  if #matchBuf == 0 then return nil end

  local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(target)
  if IsSecret(role) == true or role == "NONE" or type(role) ~= "string" then
    role = nil
  end
  NarrowCandidates(role, rosterRole)

  NarrowCandidates(SafeTargetRace(target), rosterRace)
  NarrowCandidates(SafeTargetSex(target), rosterSex)

  if #matchBuf == 1 then
    return matchBuf[1]
  end
  return nil
end

local function TargetNameAllowed(caster)
  if not UnitShouldDisplaySpellTargetName then return true end
  local shown = UnitShouldDisplaySpellTargetName(caster)
  return IsSecret(shown) == true or shown ~= false
end

local function ReadCast(caster)
  local name, _, texture, startMS, endMS = UnitCastingInfo(caster)
  if name ~= nil then
    return {
      name = name,
      texture = texture,
      startMS = startMS,
      endMS = endMS,
      durationObj = UnitCastingDuration and UnitCastingDuration(caster) or nil,
    }
  end

  name, _, texture, startMS, endMS = UnitChannelInfo(caster)
  if name ~= nil then
    return {
      name = name,
      texture = texture,
      startMS = startMS,
      endMS = endMS,
      durationObj = UnitChannelDuration and UnitChannelDuration(caster) or nil,
    }
  end
  return nil
end

local function Resolve(caster, generation)
  if casterGeneration[caster] ~= generation then return end
  local cast = ReadCast(caster)
  if not cast then
    ClearCaster(caster)
    return
  end
  if not TargetNameAllowed(caster) then
    HideCasterIcon(caster)
    return
  end

  local unit = ClassifyTarget(caster)
  if not unit then
    HideCasterIcon(caster)
    return
  end
  ShowFor(caster, unit, cast)
end

local function ScheduleResolve(caster, firstDelay)
  local generation = casterGeneration[caster] or 0
  Schedule(firstDelay, function() Resolve(caster, generation) end)
  Schedule(firstDelay + VERIFY_DELAY, function() Resolve(caster, generation) end)
end

local function OnCastStart(caster)
  ClearCaster(caster)
  if not IsUnitToken(caster) then return end

  local hostile = UnitCanAttack and UnitCanAttack("player", caster)
  if IsSecret(hostile) ~= true and hostile ~= true then return end
  if not TargetNameAllowed(caster) then return end

  trackedCasters[caster] = true
  casterGeneration[caster] = casterGeneration[caster] or 0
  ScheduleResolve(caster, PICKUP_DELAY)
end

local function OnRetarget(caster)
  if not trackedCasters[caster] then return end
  casterGeneration[caster] = (casterGeneration[caster] or 0) + 1
  ScheduleResolve(caster, RETARGET_DELAY)
end

local function AdoptIfCasting(unit)
  if not IsUnitToken(unit) then return end
  if ReadCast(unit) then
    OnCastStart(unit)
  end
end

local function SeedNameplates()
  wipe(nameplateUnits)
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
  local plates = C_NamePlate.GetNamePlates()
  if type(plates) ~= "table" then return end
  for i = 1, #plates do
    local token = plates[i] and plates[i].namePlateUnitToken
    if IsUnitToken(token) then
      nameplateUnits[token] = true
      AdoptIfCasting(token)
    end
  end
end

local function StartRuntime()
  if active then return end
  active = true
  RebuildRoster()
  SetHotEvents(true)
  SeedNameplates()
end

local function StopRuntime()
  if not active then return end
  active = false
  SetHotEvents(false)
  ClearAll()
  wipe(nameplateUnits)
end

function TS.RefreshConfig(reseed)
  ReadSettings()
  SetControlEvents(settings.enabled)
  if ShouldRun() then
    if active then
      if reseed == true then
        RebuildRoster()
        ClearAll()
        SeedNameplates()
      else
        RefreshVisibleIcons()
      end
    else
      StartRuntime()
    end
  else
    StopRuntime()
  end
end

function TS.IsActive()
  return active == true
end

function TS.Clear()
  ClearAll()
end

function TS.DebugSnapshot()
  ReadSettings()
  local plates = 0
  for _ in pairs(nameplateUnits) do
    plates = plates + 1
  end
  local activeCasts = 0
  for _ in pairs(activeByCaster) do
    activeCasts = activeCasts + 1
  end
  local frames = {}
  for i = 1, #PARTY_UNITS do
    local unit = PARTY_UNITS[i]
    local frame = FrameForPartyUnit(unit)
    frames[unit] = frame and (frame.GetName and frame:GetName() or true) or false
  end
  local inInstance, instanceType
  if IsInInstance then
    inInstance, instanceType = IsInInstance()
  end
  return {
    enabled = settings.enabled,
    mode = settings.mode,
    textEnabled = settings.textEnabled,
    textTickerActive = textTicker ~= nil,
    activeTextIcons = activeTextCount,
    roleAllows = RoleAllows(),
    active = active,
    hotRegistered = hotRegistered,
    controlRegistered = controlRegistered,
    shouldRun = ShouldRun(),
    inGroup = IsInGroup and IsInGroup() or false,
    inRaid = IsInRaid and IsInRaid() or false,
    inInstance = inInstance == true,
    instanceType = instanceType,
    trackedNameplates = plates,
    activeCasts = activeCasts,
    partyFrames = frames,
  }
end

function TS.ShowTest(unit, seconds)
  ReadSettings()
  unit = IsUnitToken(unit) and unit or "player"
  local frame = FrameForPartyUnit(unit) or FirstPartyFrame()
  if not frame then return false, "no party frame" end
  local caster = "__MSUF_TS_TEST"
  ClearCaster(caster)
  local icon = AcquireIcon(frame)
  if not icon then return false, "no free icon" end
  icon._msufTSCaster = caster
  icon.tex:SetTexture(FALLBACK_ICON)
  ApplyIconFrame(icon, frame)
  local now = GetTime and GetTime() or 0
  local duration = tonumber(seconds) or 8
  ApplyCooldown(icon.cooldown, nil, now * 1000, (now + duration) * 1000)
  SetIconTiming(icon, nil, now * 1000, (now + duration) * 1000)
  SetShown(icon, true)
  activeByCaster[caster] = { icon = icon, frame = frame, unit = frame.unit or unit }
  LayoutFrame(frame)
  return true, frame.unit or unit
end

function TS.HideTest()
  ClearCaster("__MSUF_TS_TEST")
end

local function InstallHooks()
  if hooksInstalled then return end
  hooksInstalled = true

  local originalRefreshVisuals = GF.RefreshVisuals
  if type(originalRefreshVisuals) == "function" then
    GF.RefreshVisuals = function(...)
      local result = originalRefreshVisuals(...)
      TS.RefreshConfig(false)
      return result
    end
    if MSUF.ExportPublic then
      MSUF.ExportPublic("MSUF_GF_RefreshVisuals", GF.RefreshVisuals)
    else
      _G.MSUF_GF_RefreshVisuals = GF.RefreshVisuals
    end
  end

  local originalRebuildAll = GF.RebuildAll
  if type(originalRebuildAll) == "function" then
    GF.RebuildAll = function(...)
      local result = originalRebuildAll(...)
      TS.RefreshConfig(true)
      return result
    end
    if MSUF.ExportPublic then
      MSUF.ExportPublic("MSUF_GF_RebuildAll", GF.RebuildAll)
    else
      _G.MSUF_GF_RebuildAll = GF.RebuildAll
    end
  end
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    TS.RefreshConfig(true)
    return
  end

  if event == "GROUP_ROSTER_UPDATE"
    or event == "PLAYER_ROLES_ASSIGNED"
    or event == "PLAYER_SPECIALIZATION_CHANGED"
    or event == "ROLE_CHANGED_INFORM" then
    TS.RefreshConfig(true)
    return
  end

  if not active or not IsUnitToken(unit) then return end

  if event == "NAME_PLATE_UNIT_ADDED" then
    nameplateUnits[unit] = true
    AdoptIfCasting(unit)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    nameplateUnits[unit] = nil
    ClearCaster(unit)
  elseif event == "UNIT_TARGET" then
    if nameplateUnits[unit] then
      OnRetarget(unit)
    end
  elseif nameplateUnits[unit] then
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
      OnCastStart(unit)
    else
      ClearCaster(unit)
    end
  end
end)

InstallHooks()
Schedule(0, function() TS.RefreshConfig(true) end)
