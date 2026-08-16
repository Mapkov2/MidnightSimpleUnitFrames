-- UF alpha element: applies frame opacity, range fade handoff, and visibility alpha rules.
-- Keep live alpha updates cheap; range and combat deferral belong to dedicated runtime modules.
local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local V = MSUF.UFVisuals or {}
local UF = V.UF or MSUF.UF

-- Unitframe alpha element.
-- Combines configured opacity, range fade, combat/target modifiers, and linked castbar alpha.
-- Keep this as a visual-only layer; load conditions decide whether frames exist/show.
local tonumber = V.tonumber or tonumber
local EMPTY_EVENTS = V.EMPTY_EVENTS or {}
local Clamp01 = V.Clamp01
local SetFrameAlpha = V.SetFrameAlpha
local SetAlphaCached = V.SetAlphaCached
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown


local Alpha = {}

-- Out-of-combat fade driver. The regen pair is registered only while at least
-- one frame's compiled spec carries oocFade, so a profile without the feature
-- pays nothing. In combat oocInCombat short-circuits OocMul to 1, which makes
-- the composition byte-identical to the pre-feature values; the only work a
-- combat transition costs is one coalesced RequestRefresh pass.
local oocInCombat = false
local oocFrames = {}
local oocFrameCount = 0
local oocDriver

-- Stateless per-apply resolve: no per-frame ooc state can race the range
-- writer, so refresh ordering across regen/range events cannot matter.
local function OocMul(cfg)
  if oocInCombat
    or not cfg
    or cfg.oocFade ~= true
    or _G.MSUF_UnitEditModeActive == true then
    return 1
  end
  return Clamp01(cfg.oocAlpha, 0.5)
end
-- Group frames own their whole-frame alpha in the GroupRangeFade element
-- (cfg.externalOoc); it composes this mul itself via CoreAlpha.
UF.OocFadeMul = OocMul

local function OocCombatFlip(entering)
  if oocInCombat == entering then
    return
  end
  oocInCombat = entering
  -- Write the tracked frames directly instead of Alpha.RequestRefresh():
  -- that path funnels into UF.RefreshElements, which DEFERS entirely while
  -- InCombat() (menu combat quiescence), so the un-fade on combat start
  -- would queue until regen and never show in combat. Alpha writes are not
  -- protected, so the direct per-frame update is combat-safe, cheaper (only
  -- tracked frames), and lands in the same frame as the regen event.
  for frame in pairs(oocFrames) do
    local poke = frame._msufUpdateGroupRangeConnection
    if poke then
      -- Group member: its composer owns the frame lane (min with range/offline).
      poke(frame, "MSUF_OOC")
    else
      Alpha.Update(frame, "MSUF_OOC")
    end
  end
end

local function OocSyncDriver()
  local want = oocFrameCount > 0
  if want and not oocDriver then
    oocDriver = CreateFrame("Frame")
    oocDriver:SetScript("OnEvent", function(_, event)
      OocCombatFlip(event == "PLAYER_REGEN_DISABLED")
    end)
  end
  if not oocDriver or (oocDriver._msufActive == true) == want then
    return
  end
  oocDriver._msufActive = want or nil
  if want then
    -- Event-tracked from here on; seed from the lockdown state because a
    -- /reload or profile swap can happen mid-combat.
    oocInCombat = InCombatLockdown and InCombatLockdown() == true or false
    oocDriver:RegisterEvent("PLAYER_REGEN_DISABLED")
    oocDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
  else
    oocDriver:UnregisterEvent("PLAYER_REGEN_DISABLED")
    oocDriver:UnregisterEvent("PLAYER_REGEN_ENABLED")
  end
end

local function OocTrackFrame(frame, hasOoc)
  local hadOoc = oocFrames[frame] == true
  if hasOoc == hadOoc then
    return
  end
  oocFrames[frame] = hasOoc or nil
  oocFrameCount = oocFrameCount + (hasOoc and 1 or -1)
  if oocFrameCount < 0 then oocFrameCount = 0 end
  OocSyncDriver()
end

local function CastbarForUnit(unit)
  if not unit then
    return nil
  end
  if unit == "target" then
    return _G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar
      or ((_G.TargetCastBar and _G.TargetCastBar._msufCastbarDriver == true) and _G.TargetCastBar)
  elseif unit == "focus" then
    return _G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar
      or ((_G.FocusCastBar and _G.FocusCastBar._msufCastbarDriver == true) and _G.FocusCastBar)
  end

  local bossIndex = tostring(unit):match("^boss(%d+)$")
  if bossIndex then
    local index = tonumber(bossIndex)
    local bossCastbars = _G.MSUF_BossCastbars
    return (bossCastbars and bossCastbars[index])
      or _G["MSUF_BossCastbar" .. bossIndex]
      or _G["MSUF_boss" .. bossIndex .. "CastBar"]
      or _G["MSUF_Boss" .. bossIndex .. "CastBar"]
  end

  return nil
end

local function CastbarRangeAlpha(frame, mul)
  if not frame then
    return 1
  end
  local rangeActive = frame._msufAlphaRangeActive
  local rangeHealthLayer = frame._msufAlphaRangeHealthLayer
  if rangeActive ~= nil or rangeHealthLayer ~= nil then
    if rangeActive ~= true or rangeHealthLayer == true then
      return 1
    end
    return Clamp01(mul, 1)
  end
  local spec = frame.MSUFSpec
  local range = spec and spec.range
  if not (range and range.active == true) or range.layerMode == "health" then
    return 1
  end
  return Clamp01(mul, 1)
end

local function ApplyCastbarRangeAlpha(frame, mul, force)
  local unit = frame and frame.MSUFUnitKey
  local castbar = CastbarForUnit(unit)
  if not (castbar and castbar.SetAlpha) then
    return false
  end
  if castbar._msufFocusKickSuppressed == true then
    return false
  end

  local alpha = CastbarRangeAlpha(frame, mul)
  SetAlphaCached(castbar, alpha, "_msufRangeCastbarAlpha", force)
  return true
end

local TEXT_ALPHA_FIELDS = {
  "nameText",
  "levelText",
  "hpTextLeft",
  "hpTextCenter",
  "hpTextRight",
  "powerTextLeft",
  "powerTextCenter",
  "powerTextRight",
  "totInlineSep",
  "totInlineText",
  "raidGroupNameText",
  "statusIndicatorText",
  "statusAFKTimerText",
}

local function StatusBarTexture(bar)
  if not (bar and bar.GetStatusBarTexture) then
    return nil
  end
  local texture = bar._msufAlphaStatusTextureObject
  if not texture then
    texture = bar:GetStatusBarTexture()
    bar._msufAlphaStatusTextureObject = texture
  end
  return texture
end

local function SetStatusBarFillAlpha(bar, alpha, field, force)
  if not bar then
    return
  end
  SetAlphaCached(StatusBarTexture(bar), alpha, field or "_msufAlphaStatusTexture", force)
end

local function SetTextLayerAlpha(frame, alpha, force)
  for i = 1, #TEXT_ALPHA_FIELDS do
    SetAlphaCached(frame and frame[TEXT_ALPHA_FIELDS[i]], alpha, "_msufAlphaText", force)
  end
end

local function SetPortraitLayerAlpha(frame, alpha, force)
  SetAlphaCached(frame and frame.MSUFPortraitHolder, alpha, "_msufAlphaPortraitHolder", force)
  SetAlphaCached(frame and frame.portrait, 1, "_msufAlphaPortraitTexture", force)
end

local function ApplyHealthFillAlpha(frame, alpha, force)
  SetStatusBarFillAlpha(frame.hpBar or frame.Health, alpha, "_msufAlphaHealth", force)
  SetStatusBarFillAlpha(frame.healthLossTrail, alpha, "_msufAlphaHealthLoss", force)
  SetStatusBarFillAlpha(frame.incomingHealBar, alpha, "_msufAlphaPrediction", force)
  SetStatusBarFillAlpha(frame.absorbBar, alpha, "_msufAlphaPrediction", force)
  SetStatusBarFillAlpha(frame.healAbsorbBar, alpha, "_msufAlphaPrediction", force)
end

local function RangeMul(frame)
  local mul = tonumber(frame and frame._msufRangeMul)
  if mul == nil then
    return 1
  elseif mul < 0 then
    return 0
  elseif mul > 1 then
    return 1
  end
  return mul
end

local function RangeFadesWholeFrame(frame)
  local rangeHealthLayer = frame and frame._msufAlphaRangeHealthLayer
  if rangeHealthLayer ~= nil then
    return rangeHealthLayer ~= true
  end
  local spec = frame and frame.MSUFSpec
  local range = spec and spec.range
  return not (range and range.layerMode == "health")
end

local function CompileAlphaRuntime(frame, spec)
  if not frame then return end
  local range = spec and spec.range
  local cfg = spec and spec.alpha or nil
  frame._msufAlphaRuntimeCfg = cfg
  frame._msufAlphaRangeActive = range and range.active == true
  frame._msufAlphaRangeHealthLayer = range and range.layerMode == "health"
  OocTrackFrame(frame, cfg ~= nil and cfg.oocFade == true)
end
UF.CompileAlphaRuntime = CompileAlphaRuntime

local function ApplyRangeOnly(frame, mul, force)
  if RangeFadesWholeFrame(frame) then
    SetFrameAlpha(frame, mul)
    ApplyCastbarRangeAlpha(frame, mul, force)
    return true
  end
  SetFrameAlpha(frame, 1)
  ApplyCastbarRangeAlpha(frame, 1, force)
  ApplyHealthFillAlpha(frame, mul, force)
  return true
end

local function ConfiguredHPAlpha(cfg)
  local hp = Clamp01(cfg and cfg.hpAlpha, 1)
  if _G.MSUF_UnitEditModeActive == true and hp < 0.35 then
    hp = 0.35
  end
  return hp
end

local function ResetFrameLayers(frame, force)
  if not frame then
    return
  end
  SetFrameAlpha(frame, 1)
  ApplyCastbarRangeAlpha(frame, 1, force)
  ApplyHealthFillAlpha(frame, 1, force)
  SetTextLayerAlpha(frame, 1, force)
  SetPortraitLayerAlpha(frame, 1, force)
  frame._msufAlphaActive = nil
  frame._msufAlphaEffective = nil
  frame._msufAlphaLastFrame = nil
  frame._msufAlphaLastHP = nil
  frame._msufAlphaLastFG = nil
end

local function ApplyAlpha(frame, cfg, force)
  if not frame then
    return
  end

  local mul = RangeMul(frame)
  local wholeFrame = RangeFadesWholeFrame(frame)
  -- Group frames (cfg.externalOoc): GroupRangeFade composes the ooc mul via
  -- CoreAlpha/UF.OocFadeMul; this element must not bake it into the frame
  -- lane, or a combat flip would read a stale composed value.
  -- Gated on the compiled flag first so a frame without the feature (and
  -- every call while it is off) pays one field test, never a call.
  local oocMul = 1
  if cfg ~= nil and cfg.oocFade == true and cfg.externalOoc ~= true then
    oocMul = OocMul(cfg)
  end

  if not (cfg and cfg.active == true) and mul == 1 and oocMul == 1 then
    if frame._msufAlphaActive == true then
      ResetFrameLayers(frame, force)
    end
    return
  end

  local hp = ConfiguredHPAlpha(cfg)
  local excludeTextPortrait = cfg and cfg.excludeTextPortrait == true

  local foregroundAlpha = excludeTextPortrait and 1 or hp

  -- min-composed: the strongest whole-frame fade wins, values never compound.
  local frameAlpha = wholeFrame and mul or 1
  if oocMul < frameAlpha then frameAlpha = oocMul end
  local hpAlpha = hp * (wholeFrame and 1 or mul)
  frame._msufAlphaEffective = frameAlpha

  if not force
    and frame._msufAlphaLastFrame == frameAlpha
    and frame._msufAlphaLastHP == hpAlpha
    and frame._msufAlphaLastFG == foregroundAlpha then
    return
  end

  SetFrameAlpha(frame, frameAlpha)
  ApplyCastbarRangeAlpha(frame, mul, force)
  ApplyHealthFillAlpha(frame, hpAlpha, force)
  SetTextLayerAlpha(frame, foregroundAlpha, force)
  SetPortraitLayerAlpha(frame, foregroundAlpha, force)

  frame._msufAlphaActive = true
  frame._msufAlphaLastFrame = frameAlpha
  frame._msufAlphaLastHP = hpAlpha
  frame._msufAlphaLastFG = foregroundAlpha
end

function Alpha.IsEnabled(frame, spec)
  local cfg = spec and spec.alpha
  return cfg and (cfg.active == true or cfg.oocFade == true)
end

function Alpha.GetEvents(frame, spec)
  return EMPTY_EVENTS
end

function Alpha.GetUnitlessEvents(frame, spec)
  return EMPTY_EVENTS
end

function Alpha.Apply(frame, spec)
  CompileAlphaRuntime(frame, spec)
  ApplyAlpha(frame, frame and frame._msufAlphaRuntimeCfg, true)
end

function Alpha.Update(frame, event)
  local force = event == "MSUF_APPLY" or event == "MSUF_FORCE_UPDATE"
    or event == "MSUF_VISUALS" or event == "MSUF_ALPHA" or event == "MSUF_RANGE_FORCE"
  local cfg = frame and frame._msufAlphaRuntimeCfg
  if cfg == nil and frame and frame.MSUFSpec then
    cfg = frame.MSUFSpec.alpha
  end
  ApplyAlpha(frame, cfg, force)
end

function Alpha.Disable(frame)
  if not frame then
    return
  end
  OocTrackFrame(frame, false)
  frame._msufAlphaLastFrame = nil
  frame._msufAlphaLastHP = nil
  frame._msufAlphaLastFG = nil
  frame._msufAlphaEffective = nil
  frame._msufAlphaRuntimeCfg = nil
  frame._msufAlphaRangeActive = nil
  frame._msufAlphaRangeHealthLayer = nil
  if RangeMul(frame) ~= 1 then
    ApplyAlpha(frame, frame.MSUFSpec and frame.MSUFSpec.alpha, true)
    return
  end
  ResetFrameLayers(frame, true)
end

UF.ApplyRangeModifier = function(frame, mul, force)
  if not frame then
    return false
  end
  mul = Clamp01(mul, 1)
  if force ~= true and frame._msufRangeMul == mul then
    return true
  end
  frame._msufRangeMul = mul
  local cfg = frame._msufAlphaRuntimeCfg or (frame.MSUFSpec and frame.MSUFSpec.alpha)
  if (cfg and (cfg.active == true or cfg.oocFade == true)) or frame._msufAlphaActive == true then
    ApplyAlpha(frame, cfg, force == true)
  elseif mul ~= 1 then
    ApplyRangeOnly(frame, mul, force == true)
  else
    ApplyRangeOnly(frame, 1, force == true)
  end
  return true
end
ExportPublic("MSUF_UF_ApplyRangeModifier", UF.ApplyRangeModifier)

local function ApplyCastbarRangeAlphaExport(castbarOrUnit, mul, force)
  local unit = type(castbarOrUnit) == "string" and castbarOrUnit
    or castbarOrUnit and castbarOrUnit.unit
  if not unit then
    return false
  end
  local frame = UF.frames and UF.frames[unit]
  if not frame and tostring(unit):match("^boss%d+$") then
    frame = UF.frames and UF.frames.boss
  end
  if not frame then
    return false
  end
  return ApplyCastbarRangeAlpha(frame, mul or RangeMul(frame), force == true)
end
ExportPublic("MSUF_UF_ApplyCastbarRangeAlpha", ApplyCastbarRangeAlphaExport)

UF.ApplyAlphaFrame = function(frame, event)
  if not frame then
    return false
  end
  Alpha.Update(frame, event or "MSUF_ALPHA")
  return true
end

UF.RegisterElement("Alpha", Alpha)

do
  local pendingAll
  local pendingUnits = {}

  local function Flush()
    local refresh = _G.MSUF_RefreshAllUnitAlphas
    if type(refresh) ~= "function" then
      pendingAll = nil
      for unit in pairs(pendingUnits) do pendingUnits[unit] = nil end
      return false
    end
    if pendingAll then
      pendingAll = nil
      for unit in pairs(pendingUnits) do pendingUnits[unit] = nil end
      return refresh()
    end
    local did = false
    for unit in pairs(pendingUnits) do
      pendingUnits[unit] = nil
      did = refresh(unit) or did
    end
    return did
  end

  function Alpha.RequestRefresh(unit)
    if unit ~= nil then
      unit = tostring(unit or "")
      if unit == "" or unit == "*" then unit = nil end
    end
    if unit then
      pendingUnits[unit] = true
    else
      pendingAll = true
    end
    local scheduleOnce = _G.MSUF_ScheduleOnce
    if type(scheduleOnce) == "function" then
      scheduleOnce("UF_ALPHA_FLUSH", Flush)
    else
      Flush()
    end
    return true
  end
end

local function RequestAlphaRefresh(unit)
  return Alpha.RequestRefresh(unit)
end
ExportPublic("MSUF_RequestAlphaRefresh", RequestAlphaRefresh)

local function RefreshCombatUnitAlphas(unit)
  if _G.MSUF_RefreshAllUnitAlphas then
    return _G.MSUF_RefreshAllUnitAlphas(unit)
  end
  return false
end
ExportPublic("MSUF_RefreshCombatUnitAlphas", RefreshCombatUnitAlphas)

local function GetDesiredUnitAlpha(key)
  local unit = key == "boss" and "boss1" or key
  if unit == "tot" or unit == "targetoftarget" then
    unit = "targettarget"
  end
  local spec = unit and UF.Config and UF.Config.GetSpec and UF.Config.GetSpec(unit)
  local cfg = spec and spec.alpha
  if not cfg then
    return 1
  end
  return Clamp01(cfg.hpAlpha, 1)
end
ExportPublic("MSUF_GetDesiredUnitAlpha", GetDesiredUnitAlpha)

local function ApplyUnitAlpha(frame, key)
  if not frame then
    return false
  end
  Alpha.Update(frame, "MSUF_ALPHA")
  return true
end
ExportPublic("MSUF_ApplyUnitAlpha", ApplyUnitAlpha)

local function AlphaUpdatePreserveMissingHP()
end
ExportPublic("MSUF_Alpha_UpdatePreserveMissingHP", AlphaUpdatePreserveMissingHP)
