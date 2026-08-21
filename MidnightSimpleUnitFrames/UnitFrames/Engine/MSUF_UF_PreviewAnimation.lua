--- UnitFrames/Engine/MSUF_UF_PreviewAnimation.lua
--- On-demand combat-state animation for edit-mode and menu preview frames.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local PA = MSUF.PreviewAnimation or {}
MSUF.PreviewAnimation = PA

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat
local floor, min, max = math.floor, math.min, math.max
local format = string.format
local type, tonumber, tostring = type, tonumber, tostring

local UPDATE_INTERVAL = 1 / 20
local NO_TARGET_GRACE = 0.35
local PREVIEW_UNITS = { "target", "focus", "targettarget", "focustarget", "pet" }
local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local PREVIEW_NAME_LABELS = {
  player = "Player Name Position",
  target = "Target Name Position",
  focus = "Focus Name Position",
  targettarget = "Target of Target Name Position",
  focustarget = "Focus Target Name Position",
  pet = "Pet Name Position",
}

local function CoreFrame(unit)
  local uf = MSUF and MSUF.UF
  if uf and type(uf.GetFrame) == "function" then
    local frame = uf.GetFrame(unit)
    if frame then return frame end
  end
  local frames = uf and uf.frames
  return unit and frames and frames[unit] or nil
end
local CASTBAR_PREVIEWS = {
  { name = "MSUF_PlayerCastbarPreview", unit = "player", label = "Test Cast" },
  { name = "MSUF_TargetCastbarPreview", unit = "target", label = "Test Cast" },
  { name = "MSUF_FocusCastbarPreview", unit = "focus", label = "Test Cast" },
}

local driver
local noTargetElapsed = 0
local editModeStopListenerRegistered
local RegisterEditModeStopListener
local percentValue = 0
local frameStateScratch = {}
local unitFrameRestoreFrames = setmetatable({}, { __mode = "k" })

PA.menuBoxes = PA.menuBoxes or setmetatable({}, { __mode = "k" })
PA.groupBoxes = PA.groupBoxes or setmetatable({}, { __mode = "k" })
PA.refreshOwners = PA.refreshOwners or setmetatable({}, { __mode = "k" })
PA.elapsed = tonumber(PA.elapsed) or 0
PA.enabled = PA.enabled == true

local function PercentValue()
  return percentValue
end

local function InCombat()
  return (InCombatLockdown and InCombatLockdown())
    or (UnitAffectingCombat and UnitAffectingCombat("player"))
    or _G.MSUF_InCombat == true
end

local function IsVisible(frame)
  return frame
    and frame.IsShown and frame:IsShown()
    and (not frame.IsVisible or frame:IsVisible())
end

local function Clamp01(v, fallback)
  v = tonumber(v)
  if v == nil then v = fallback or 0 end
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function Triangle(elapsed, speed, offset)
  local p = ((tonumber(elapsed) or 0) * speed + (offset or 0)) % 1
  if p < 0.5 then
    return p * 2
  end
  return (1 - p) * 2
end

local function Saw(elapsed, speed, offset)
  return (((tonumber(elapsed) or 0) * speed + (offset or 0)) % 1)
end

local AURA_DURATIONS = {
  buff = { 120, 76, 45, 28, 180, 14, 95, 36 },
  debuff = { 32, 18, 11, 7, 44, 24, 15, 9 },
}
local AURA_KIND_OFFSETS = { buff = 0.11, debuff = 0.37 }

local function AuraKind(kind)
  kind = tostring(kind or ""):lower()
  if kind == "buffs" then return "buff" end
  if kind == "debuffs" then return "debuff" end
  return AURA_DURATIONS[kind] and kind or "buff"
end

local function FormatAuraTime(remaining, duration, decimalThreshold)
  remaining = tonumber(remaining) or 0
  duration = tonumber(duration) or 0
  if decimalThreshold == true then
    decimalThreshold = 60
  elseif decimalThreshold == false or decimalThreshold == nil then
    decimalThreshold = 3
  else
    decimalThreshold = max(0, tonumber(decimalThreshold) or 3)
  end
  if duration <= 0 then return "" end
  if remaining >= 3600 then
    return tostring(max(1, floor((remaining + 1800) / 3600))) .. "h"
  elseif remaining >= 60 then
    return tostring(max(1, floor((remaining + 30) / 60))) .. "m"
  elseif decimalThreshold > 0 and remaining < decimalThreshold then
    return format("%.1f", max(0.1, remaining))
  end
  return tostring(max(1, floor(remaining + 0.5)))
end

function PA.IsEnabled()
  return PA.enabled == true
end

function PA.Elapsed()
  return tonumber(PA.elapsed) or 0
end

function PA.BuildFrameState(frame, index, kind, scratch, elapsed)
  scratch = scratch or frameStateScratch
  local i = tonumber(index) or tonumber(frame and frame._msufGFPreviewIndex) or 1
  elapsed = tonumber(elapsed) or 0
  local offset = (i * 0.073) + ((tostring(kind or frame and frame.MSUFUnitKey or ""):byte(1) or 0) * 0.001)
  local hpWave = Triangle(elapsed, 0.145, offset)
  local powerWave = Triangle(elapsed, 0.21, offset + 0.31)
  local castPct = Saw(elapsed, 0.34, offset + 0.18)
  local pulse = Triangle(elapsed, 1.15, offset + 0.09)

  scratch.elapsed = elapsed
  scratch.hpPct = Clamp01(0.23 + hpWave * 0.69, 0.70)
  scratch.powerPct = Clamp01(0.16 + powerWave * 0.78, 0.74)
  scratch.healPct = Clamp01(0.04 + Triangle(elapsed, 0.32, offset + 0.44) * 0.12, 0.08)
  scratch.absorbPct = Clamp01(0.05 + Triangle(elapsed, 0.27, offset + 0.67) * 0.11, 0.10)
  scratch.castPct = Clamp01(castPct, 0.50)
  scratch.castDuration = 2.8
  scratch.castRemaining = max(0, scratch.castDuration * (1 - scratch.castPct))
  scratch.pulse = pulse
  scratch.phase = Saw(elapsed, 0.18, offset)
  return scratch
end

function PA.FrameState(frame, index, kind, scratch)
  if PA.enabled ~= true then return nil end
  return PA.BuildFrameState(frame, index, kind, scratch, PA.Elapsed())
end

function PA.BuildAuraState(kind, index, scratch, options, elapsed)
  kind = AuraKind(kind)
  scratch = scratch or {}
  options = options or {}

  local i = tonumber(index) or 1
  local durations = AURA_DURATIONS[kind] or AURA_DURATIONS.buff
  local duration = tonumber(options.duration) or durations[((i - 1) % #durations) + 1] or 30
  if duration <= 0 then duration = 30 end
  elapsed = tonumber(elapsed) or 0
  local oneShot = options.oneShot == true
  local offsetFrac = oneShot and 0 or (((i * 0.173) + (AURA_KIND_OFFSETS[kind] or 0)) % 1)
  local auraElapsed = oneShot and min(duration, max(0, elapsed))
    or ((elapsed + duration * offsetFrac) % duration)
  local complete = oneShot and auraElapsed >= duration
  local remaining = complete and 0 or max(0.1, duration - auraElapsed)
  local remainingFrac = Clamp01(remaining / duration, 1)
  local elapsedFrac = Clamp01(auraElapsed / duration, 0)
  local pandemicThreshold = Clamp01(options.pandemicThreshold, 0.30)
  local stacks = ""
  if kind == "buff" then
    if i % 3 == 1 then stacks = tostring(2 + floor(Triangle(elapsed, 0.42, i * 0.07) * 2.99)) end
  elseif kind == "debuff" then
    if i % 2 == 1 then stacks = tostring(1 + floor(Triangle(elapsed, 0.55, i * 0.09) * 3.99)) end
  end

  scratch.kind = kind
  scratch.elapsed = auraElapsed
  scratch.totalElapsed = elapsed
  scratch.duration = duration
  scratch.remaining = remaining
  scratch.remainingFrac = remainingFrac
  scratch.elapsedFrac = elapsedFrac
  scratch.progress = elapsedFrac
  scratch.swipeFrac = remainingFrac
  scratch.complete = complete
  scratch.pandemicActive = not complete and remainingFrac <= pandemicThreshold + 0.000001
  scratch.text = complete and "" or FormatAuraTime(remaining, duration,
    options.decimalThreshold ~= nil and options.decimalThreshold or options.decimalSeconds)
  scratch.stacks = stacks
  return scratch
end

function PA.AuraState(kind, index, scratch, options)
  if PA.enabled ~= true then return nil end
  return PA.BuildAuraState(kind, index, scratch, options, PA.Elapsed())
end

local function NotifyRefreshOwners()
  for owner, fn in pairs(PA.refreshOwners) do
    if type(fn) == "function" then
      fn(owner, PA.enabled == true)
    end
  end
end

function PA.RegisterRefreshOwner(owner, fn)
  if owner and type(fn) == "function" then
    PA.refreshOwners[owner] = fn
    fn(owner, PA.enabled == true)
  end
end

function PA.UnregisterRefreshOwner(owner)
  if owner then PA.refreshOwners[owner] = nil end
end

function PA.RegisterMenuBox(box)
  if box then PA.menuBoxes[box] = true end
end

function PA.UnregisterMenuBox(box)
  if box then PA.menuBoxes[box] = nil end
end

function PA.RegisterGroupBox(box)
  if box then PA.groupBoxes[box] = true end
end

function PA.UnregisterGroupBox(box)
  if box then PA.groupBoxes[box] = nil end
end

local function HasVisibleMenuBox()
  for box in pairs(PA.menuBoxes) do
    if IsVisible(box) then return true end
  end
  return false
end

local function HasVisibleGroupBox()
  for box in pairs(PA.groupBoxes) do
    if IsVisible(box) then return true end
  end
  return false
end

local function GroupPreviewActive()
  local gf = MSUF and MSUF.GF
  local active = gf and gf._previewActive
  return active and (active.party or active.raid or active.mythicraid) and true or false
end

local function EditModePreviewActive()
  if _G.MSUF_UnitEditModeActive == true then return true end
  local em2 = _G.MSUF_EM2
  return em2 and em2.State and type(em2.State.IsActive) == "function" and em2.State.IsActive() == true
end

local function BossPreviewActive()
  return _G.MSUF_BossTestMode == true or _G.MSUF2_BossUnitframePreviewActive == true
end

local function EditModeAnimationTargetActive()
  if not EditModePreviewActive() then return false end
  return PA.source == "edit_mode"
    or _G.MSUF_UnitPreviewActive == true
    or _G.MSUF_PreviewTestMode == true
end

local function HasVisibleTarget()
  if PA.source == "edit_mode" then return EditModeAnimationTargetActive() end
  if HasVisibleMenuBox() then return true end
  if HasVisibleGroupBox() then return true end
  if GroupPreviewActive() then return true end
  if BossPreviewActive() then return true end
  return EditModeAnimationTargetActive()
end

local function PrepareEditModePreviewForAnimation()
  if not EditModePreviewActive() then return end
  if RegisterEditModeStopListener then RegisterEditModeStopListener() end
  if _G.MSUF_UnitPreviewActive ~= true then
    ExportPublic("MSUF_UnitPreviewActive", true)
  end

  if type(_G.MSUF_SyncAllUnitPreviewsAsync) == "function" then
    _G.MSUF_SyncAllUnitPreviewsAsync()
  elseif type(_G.MSUF_SyncAllUnitPreviews) == "function" then
    _G.MSUF_SyncAllUnitPreviews()
  end

  if type(_G.MSUF_GF_EM2_IsPreviewShown) == "function"
    and _G.MSUF_GF_EM2_IsPreviewShown() == true
    and type(_G.MSUF_GF_EM2_ShowPreview) == "function" then
    _G.MSUF_GF_EM2_ShowPreview()
  end

  if type(_G.MSUF_EM2_ReforcePreviewFrames) == "function" then
    _G.MSUF_EM2_ReforcePreviewFrames()
  end
end

local function SetBar(bar, value, maxValue, animate)
  if not bar then return false end
  maxValue = tonumber(maxValue) or 1
  if maxValue <= 0 then maxValue = 1 end
  value = max(0, min(maxValue, tonumber(value) or 0))
  if bar.SetMinMaxValues then bar:SetMinMaxValues(0, maxValue) end
  if bar.SetValue then bar:SetValue(value, animate == true and bar._msufSmoothInterp or nil) end
  if bar.Show then bar:Show() end
  return true
end

local function SetRegionShown(region, shown, alpha)
  if not region then return end
  if region.SetAlpha and alpha then region:SetAlpha(alpha) end
  if region.SetShown then
    region:SetShown(shown == true)
  elseif shown and region.Show then
    region:Show()
  elseif region.Hide then
    region:Hide()
  end
end

local function StoreRegionState(region)
  if not region then return nil end
  local state = { region = region }
  if region.GetAlpha then state.alpha = region:GetAlpha() end
  if region.IsShown then state.shown = region:IsShown() end
  return state
end

local function RestoreRegionState(state)
  local region = state and state.region
  if not region then return end
  if region.SetAlpha and state.alpha ~= nil then region:SetAlpha(state.alpha) end
  if state.shown ~= nil then SetRegionShown(region, state.shown == true) end
end

local function StoreStatusBarState(bar)
  if not bar then return nil end
  local state = { bar = bar }
  if bar.GetMinMaxValues then state.minValue, state.maxValue = bar:GetMinMaxValues() end
  if bar.GetValue then state.value = bar:GetValue() end
  if bar.IsShown then state.shown = bar:IsShown() end
  if bar.GetAlpha then state.alpha = bar:GetAlpha() end
  local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
  if tex and tex.GetAlpha then state.fillAlpha = tex:GetAlpha() end
  return state
end

local function RuntimeStatusBarValues(frame, bar, role)
  if not bar then return nil, nil end
  local unit = frame and frame.MSUFUnitKey
  local value, maxValue
  if role == "health" and unit then
    if bar._msufHealthValueUnit == unit then value = bar._msufHealthValue end
    if bar._msufHealthMaxReady == true and bar._msufHealthMaxUnit == unit then maxValue = bar._msufHealthMax end
  elseif role == "power" and unit then
    if bar._msufPowerMaxReady == true and bar._msufPowerMaxUnit == unit then maxValue = bar._msufPowerMax end
  end
  if value == nil then
    if bar._msufDirectValuePlain == true then
      value = bar._msufDirectValue
    elseif bar._msufValuePlain == true then
      value = bar._msufValue
    end
  end
  if maxValue == nil then
    if bar._msufDirectMaxValuePlain == true then
      maxValue = bar._msufDirectMaxValue
    elseif bar._msufMaxValuePlain == true then
      maxValue = bar._msufMaxValue
    end
  end
  return value, maxValue
end

local function RestoreStatusBarState(state, frame, role)
  local bar = state and state.bar
  if not bar then return end
  local value, maxValue = RuntimeStatusBarValues(frame, bar, role)
  value = value ~= nil and value or state.value
  maxValue = maxValue ~= nil and maxValue or state.maxValue
  if bar.SetMinMaxValues and state.minValue ~= nil and maxValue ~= nil then
    bar:SetMinMaxValues(state.minValue, maxValue)
  end
  if bar.SetValue and value ~= nil then bar:SetValue(value) end
  if bar.SetAlpha and state.alpha ~= nil then bar:SetAlpha(state.alpha) end
  local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
  if tex and tex.SetAlpha and state.fillAlpha ~= nil then tex:SetAlpha(state.fillAlpha) end
  if state.shown ~= nil then SetRegionShown(bar, state.shown == true) end
end

local function StoreFontStringState(fontString)
  if not (fontString and fontString.SetText) then return nil end
  local state = { region = fontString }
  if fontString.GetText then state.text = fontString:GetText() end
  if fontString.GetAlpha then state.alpha = fontString:GetAlpha() end
  if fontString.IsShown then state.shown = fontString:IsShown() end
  return state
end

local function RestoreFontStringState(state)
  local fontString = state and state.region
  if not (fontString and fontString.SetText) then return end
  fontString:SetText(state.text or "")
  if fontString.SetAlpha and state.alpha ~= nil then fontString:SetAlpha(state.alpha) end
  if state.shown ~= nil then SetRegionShown(fontString, state.shown == true) end
end

local function StoreTextSlotStates(slots, count)
  if type(slots) ~= "table" then return nil end
  local states
  count = tonumber(count) or #slots
  for i = 1, count do
    local state = StoreFontStringState(slots[i])
    if state then
      states = states or {}
      states[#states + 1] = state
    end
  end
  return states
end

local function RestoreTextSlotStates(states)
  if type(states) ~= "table" then return end
  for i = 1, #states do RestoreFontStringState(states[i]) end
end

local UNIT_TEXT_RUNTIME_FIELDS = {
  "healthMissing",
}

local function StoreTextRuntimeState(frame, restore)
  local rt = frame and frame._msufTextRuntime
  if not rt then return end
  local values = {}
  for i = 1, #UNIT_TEXT_RUNTIME_FIELDS do
    local key = UNIT_TEXT_RUNTIME_FIELDS[i]
    values[key] = rt[key]
  end
  restore.textRuntime = { runtime = rt, values = values }
  restore.healthTextSlots = StoreTextSlotStates(rt.healthSlots, rt.healthSlotCount)
  restore.powerTextSlots = StoreTextSlotStates(rt.powerSlots, rt.powerSlotCount)
end

local function RestoreTextRuntimeState(restore)
  local textRuntime = restore and restore.textRuntime
  local rt = textRuntime and textRuntime.runtime
  if rt then
    local values = textRuntime.values or {}
    for i = 1, #UNIT_TEXT_RUNTIME_FIELDS do
      local key = UNIT_TEXT_RUNTIME_FIELDS[i]
      rt[key] = values[key]
    end
  end
  RestoreTextSlotStates(restore and restore.healthTextSlots)
  RestoreTextSlotStates(restore and restore.powerTextSlots)
end

local function ClearEditModePreviewFlags()
  ExportPublic("MSUF_UnitPreviewActive", false)
  ExportPublic("MSUF_PreviewTestMode", false)
  ExportPublic("MSUF_BossTestMode", false)
  ExportPublic("MSUF2_BossUnitframePreviewActive", nil)
end

local function RuntimeStopReason(frame)
  return frame and frame._msufGFKind and "MSUF_GF_UNIT_IDENTITY" or "MSUF_UNIT_IDENTITY_FAST"
end

local function RefreshUnitFrameRuntimeAfterPreview(frame)
  if not frame then return end
  local unit = frame.MSUFUnitKey
  local reason = RuntimeStopReason(frame)

  frame._msufPreviewNameText = nil

  local hp, hpMax, calc
  local updateHealth = frame._msufUpdateHealth
  if type(updateHealth) == "function" then
    hp, hpMax, calc = updateHealth(frame, reason, unit)
  end
  local updateHealthText = frame._msufUpdateHealthText
  if type(updateHealthText) == "function" then
    updateHealthText(frame, reason, unit, hp, hpMax)
  end

  local power, powerMax, powerType, powerToken, powerMetaChanged
  local updatePower = frame._msufUpdatePower
  if type(updatePower) == "function" then
    power, powerMax, powerType, powerToken, powerMetaChanged = updatePower(frame, reason, unit)
  end
  local updatePowerText = frame._msufUpdatePowerText
  if type(updatePowerText) == "function" then
    updatePowerText(frame, reason, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
  end

  local updateName = frame._msufUpdateNameText
  if type(updateName) == "function" then
    updateName(frame, reason, unit)
  end

  local updatePrediction = frame._msufUpdatePrediction
  if type(updatePrediction) == "function" then
    updatePrediction(frame, reason, unit, hp, hpMax, calc)
  end
end

local function EnsureCombatTexture(tex)
  if not tex or tex._msufPreviewAnimCombatTexture then return end
  if tex.SetAtlas then
    tex:SetAtlas("UI-HUD-UnitFrame-Player-PortraitCombatIcon")
  elseif tex.SetTexture then
    tex:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    if tex.SetTexCoord then tex:SetTexCoord(0.5, 1, 0, 0.5) end
  end
  tex._msufPreviewAnimCombatTexture = true
end

local function EnsureIncomingResTexture(tex)
  if not tex or tex._msufPreviewAnimIncomingResTexture then return end
  if tex.SetTexture then tex:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez") end
  if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
  tex._msufPreviewAnimIncomingResTexture = true
end

local function ApplyStatus(frame, state)
  local pulse = 0.55 + (tonumber(state and state.pulse) or 0) * 0.45
  local combat = frame and frame.combatStateIndicatorIcon
  if combat then
    EnsureCombatTexture(combat)
    SetRegionShown(combat, true, pulse)
  end

  local incoming = frame and (frame.incomingResIndicatorIcon or frame.resurrectIcon)
  if incoming then
    EnsureIncomingResTexture(incoming)
    SetRegionShown(incoming, (state and state.phase or 0) > 0.70, 0.88)
  end

  local ready = frame and frame.readyCheckIcon
  if ready then
    SetRegionShown(ready, (state and state.phase or 0) > 0.46 and (state and state.phase or 0) < 0.62, 0.88)
  end
end

local function ApplyPrediction(frame, hpMax, state)
  local spec = frame and frame.MSUFSpec
  local prediction = spec and spec.prediction
  if not (prediction and prediction.enabled == true) then return end
  if prediction.heal == true and frame.incomingHealBar then
    SetBar(frame.incomingHealBar, hpMax * (state.healPct or 0.08), hpMax)
  end
  if prediction.absorb == true and frame.absorbBar then
    SetBar(frame.absorbBar, hpMax * (state.absorbPct or 0.10), hpMax)
  end
  if prediction.healAbsorb == true and frame.healAbsorbBar then
    SetBar(frame.healAbsorbBar, hpMax * 0.07, hpMax)
  end
end

local function ApplyText(frame, hp, hpMax, power, powerMax, hpPct, powerPct)
  local text = MSUF and MSUF.UFText
  local rt = frame and frame._msufTextRuntime
  if not (text and rt and text.UpdateTextSlots) then return end

  rt.healthMissing = max(0, (hpMax or 0) - (hp or 0))
  percentValue = floor((hpPct or 0) * 100 + 0.5)
  text.UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.MSUFUnitKey, PercentValue, rt.healthNeedsPercent, rt)

  percentValue = floor((powerPct or 0) * 100 + 0.5)
  text.UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.MSUFUnitKey, PercentValue, rt.powerNeedsPercent, rt)
end

local function ApplyPreviewName(frame, kind)
  local text = MSUF and MSUF.UFText
  local label = PREVIEW_NAME_LABELS[kind or frame and frame.MSUFUnitKey]
  if not (frame and label and text and type(text.UpdateName) == "function") then
    if frame then frame._msufPreviewNameText = nil end
    return false
  end
  frame._msufPreviewNameText = label
  text.UpdateName(frame, "MSUF_PREVIEW_NAME", frame.MSUFUnitKey)
  return true
end

local function SetTextIfChanged(fontString, text)
  if fontString and fontString.SetText then fontString:SetText(text or "") end
end

local function StoreUnitFrameRestore(frame)
  if not frame then return nil end
  local restore = frame._msufPreviewAnimUnitRestore
  if restore then return restore end

  restore = {
    source = PA.source,
    unit = frame.MSUFUnitKey,
    healthBar = StoreStatusBarState(frame.hpBar or frame.Health or frame.health),
    powerBar = StoreStatusBarState(frame.targetPowerBar or frame.powerBar or frame.Power or frame.power),
    incomingHealBar = StoreStatusBarState(frame.incomingHealBar),
    absorbBar = StoreStatusBarState(frame.absorbBar),
    healAbsorbBar = StoreStatusBarState(frame.healAbsorbBar),
    nameText = StoreFontStringState(frame.nameText),
    nameTextUnit = frame._msufNameTextUnit,
    nameStatusUnit = frame._msufNameStatusUnit,
    nameStatusHidden = frame._msufNameStatusHidden,
    previewNameText = frame._msufPreviewNameText,
    combatIcon = StoreRegionState(frame.combatStateIndicatorIcon),
    incomingResIcon = StoreRegionState(frame.incomingResIndicatorIcon or frame.resurrectIcon),
    readyCheckIcon = StoreRegionState(frame.readyCheckIcon),
  }
  StoreTextRuntimeState(frame, restore)
  frame._msufPreviewAnimUnitRestore = restore
  unitFrameRestoreFrames[frame] = true
  return restore
end

local function RestoreUnitFrame(frame, refreshRuntime)
  local restore = frame and frame._msufPreviewAnimUnitRestore
  if not restore then return false end

  RestoreStatusBarState(restore.healthBar, frame, "health")
  RestoreStatusBarState(restore.powerBar, frame, "power")
  RestoreStatusBarState(restore.incomingHealBar, frame)
  RestoreStatusBarState(restore.absorbBar, frame)
  RestoreStatusBarState(restore.healAbsorbBar, frame)
  frame._msufPreviewNameText = restore.previewNameText
  frame._msufNameTextUnit = restore.nameTextUnit
  frame._msufNameStatusUnit = restore.nameStatusUnit
  frame._msufNameStatusHidden = restore.nameStatusHidden
  RestoreFontStringState(restore.nameText)
  RestoreTextRuntimeState(restore)
  RestoreRegionState(restore.combatIcon)
  RestoreRegionState(restore.incomingResIcon)
  RestoreRegionState(restore.readyCheckIcon)

  frame._msufPreviewNameText = nil
  if refreshRuntime == true then
    RefreshUnitFrameRuntimeAfterPreview(frame)
  end
  frame._msufPreviewAnimState = nil
  frame._msufPreviewAnimUnitRestore = nil
  unitFrameRestoreFrames[frame] = nil
  return true
end

local function RestoreUnitAnimationFrames(refreshRuntime)
  local any = false
  for frame in pairs(unitFrameRestoreFrames) do
    any = RestoreUnitFrame(frame, refreshRuntime) or any
  end
  return any
end

local function CastbarTimeEnabled(unit)
  local db = _G.MSUF_DB
  local g = db and db.general
  if not g then return true end
  if unit == "player" then return g.showPlayerCastTime ~= false end
  if unit == "target" then return g.showTargetCastTime ~= false end
  if unit == "focus" then return g.showFocusCastTime ~= false end
  return g.showBossCastTime ~= false
end

local function FormatCastbarPreviewTime(frame, remaining, total)
  local fmt = "CURRENT"
  if type(_G.MSUF_GetCastbarTimeFormat) == "function" then
    fmt = _G.MSUF_GetCastbarTimeFormat(frame and frame.MSUFUnitKey) or fmt
  end
  if frame then frame._msufCastTimeFormat = fmt end
  if type(_G.MSUF_FormatCastbarTimeText) == "function" then
    return _G.MSUF_FormatCastbarTimeText(fmt, remaining, total)
  end
  return format("%.1f", tonumber(remaining) or 0)
end

local function StoreCastbarRestore(frame)
  if not frame then return nil end
  local restore = frame._msufPreviewAnimCastRestore
  if restore then return restore end
  restore = {}
  frame._msufPreviewAnimCastRestore = restore
  restore.source = PA.source
  restore.testMode = frame.MSUF_testMode
  restore.testActive = frame._msufTestActive
  restore.testStart = frame.MSUF_testStart
  restore.testDur = frame.MSUF_testDur
  if frame.GetScript then restore.onUpdate = frame:GetScript("OnUpdate") end

  local bar = frame.statusBar
  if bar then
    if bar.GetMinMaxValues then restore.minValue, restore.maxValue = bar:GetMinMaxValues() end
    if bar.GetValue then restore.value = bar:GetValue() end
    restore.hideFillTexture = bar.MSUF_hideFillTexture
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if tex and tex.GetAlpha then restore.fillAlpha = tex:GetAlpha() end
  end
  if frame.castText and frame.castText.GetText then restore.castText = frame.castText:GetText() end
  if frame.timeText then
    if frame.timeText.GetText then restore.timeText = frame.timeText:GetText() end
    if frame.timeText.GetAlpha then restore.timeAlpha = frame.timeText:GetAlpha() end
    if frame.timeText.IsShown then restore.timeShown = frame.timeText:IsShown() end
  end
  if frame.latencyBar then
    if frame.latencyBar.GetWidth then restore.latencyWidth = frame.latencyBar:GetWidth() end
    if frame.latencyBar.IsShown then restore.latencyShown = frame.latencyBar:IsShown() end
  end
  return restore
end

local function OwnCastbarPreviewFrame(frame, restore)
  if not (frame and restore and restore.source == "edit_mode") then return end
  frame.MSUF_testMode = nil
  frame._msufTestActive = nil
  frame.MSUF_testStart = nil
  frame.MSUF_testDur = nil
  if frame.SetScript then frame:SetScript("OnUpdate", nil) end
end

local function RestoreCastbarFrame(frame)
  local restore = frame and frame._msufPreviewAnimCastRestore
  if not restore then return end

  local bar = frame.statusBar
  if bar then
    if bar.SetMinMaxValues and restore.minValue ~= nil and restore.maxValue ~= nil then
      bar:SetMinMaxValues(restore.minValue, restore.maxValue)
    end
    if bar.SetValue and restore.value ~= nil then bar:SetValue(restore.value) end
    bar.MSUF_hideFillTexture = restore.hideFillTexture
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if tex and tex.SetAlpha and restore.fillAlpha ~= nil then tex:SetAlpha(restore.fillAlpha) end
  end
  SetTextIfChanged(frame.castText, restore.castText or "")
  if frame.timeText then
    SetTextIfChanged(frame.timeText, restore.timeText or "")
    if frame.timeText.SetAlpha and restore.timeAlpha ~= nil then frame.timeText:SetAlpha(restore.timeAlpha) end
    if restore.timeShown ~= nil then SetRegionShown(frame.timeText, restore.timeShown == true) end
  end
  if frame.latencyBar then
    if frame.latencyBar.SetWidth and restore.latencyWidth ~= nil then frame.latencyBar:SetWidth(restore.latencyWidth) end
    if restore.latencyShown ~= nil then SetRegionShown(frame.latencyBar, restore.latencyShown == true) end
  end
  if restore.source == "edit_mode" then
    frame.MSUF_testMode = nil
    frame._msufTestActive = nil
    frame.MSUF_testStart = nil
    frame.MSUF_testDur = nil
    if frame.SetScript then frame:SetScript("OnUpdate", nil) end
  else
    frame.MSUF_testMode = restore.testMode
    frame._msufTestActive = restore.testActive
    frame.MSUF_testStart = restore.testStart
    frame.MSUF_testDur = restore.testDur
    if frame.SetScript and restore.onUpdate then frame:SetScript("OnUpdate", restore.onUpdate) end
  end
  if type(_G.MSUF_ResetCastbarGlowFade) == "function" then _G.MSUF_ResetCastbarGlowFade(frame) end
  frame._msufPreviewAnimCastState = nil
  frame._msufPreviewAnimCastRestore = nil
  frame._msufPreviewAnimCastLabel = nil
  frame._msufPreviewAnimCastLabelRevision = nil
end

local function ApplyCastbarPreviewLabel(frame, label)
  label = label or "Test Cast"
  local revision = _G.MSUF_CastbarStyleRevision or 1
  local applyTexts = _G.MSUF_CB_ApplyTexts
  if type(applyTexts) ~= "function" then
    -- The shared formatter is loaded before this module in production. Keep
    -- the fallback uncached so an unusual late load repairs itself next tick.
    frame._msufPreviewAnimCastLabel = nil
    frame._msufPreviewAnimCastLabelRevision = nil
    SetTextIfChanged(frame.castText, label)
    return
  end
  if frame._msufPreviewAnimCastLabel == label
    and frame._msufPreviewAnimCastLabelRevision == revision then
    return
  end
  frame._msufPreviewAnimCastLabel = label
  frame._msufPreviewAnimCastLabelRevision = revision
  applyTexts(frame, nil, label, nil)
end

local function ApplyCastbarPreviewFrame(frame, index, kind, label)
  if PA.enabled ~= true or InCombat() or not IsVisible(frame) or not frame.statusBar then return false end
  local ownsEditModeTest = PA.source == "edit_mode"
  if not ownsEditModeTest and (frame.MSUF_testMode == true or frame._msufTestActive == true) then return false end

  local state = PA.FrameState(frame, index, kind, frame._msufPreviewAnimCastState or {})
  frame._msufPreviewAnimCastState = state
  local restore = StoreCastbarRestore(frame)
  OwnCastbarPreviewFrame(frame, restore)

  local duration = tonumber(state.castDuration) or 2.8
  if duration <= 0 then duration = 2.8 end
  local remaining = max(0, min(duration, tonumber(state.castRemaining) or (duration * 0.5)))
  local elapsed = duration - remaining

  local bar = frame.statusBar
  if bar.SetMinMaxValues then bar:SetMinMaxValues(0, duration) end
  if bar.SetValue then bar:SetValue(elapsed) end
  bar.MSUF_hideFillTexture = nil
  local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
  if tex and tex.SetAlpha then tex:SetAlpha(1) end

  ApplyCastbarPreviewLabel(frame, label)
  if frame.timeText then
    local showTime = CastbarTimeEnabled(frame.MSUFUnitKey or kind)
    frame.timeText:Show()
    if frame.timeText.SetAlpha then frame.timeText:SetAlpha(showTime and 1 or 0) end
    SetTextIfChanged(frame.timeText, showTime and FormatCastbarPreviewTime(frame, remaining, duration) or "")
  end
  if frame.icon and frame.icon.Show then frame.icon:Show() end
  -- Spark creation, geometry, and visibility are owned by the cold castbar
  -- style pass. Preview animation only advances the fill and must not override
  -- the user's castbarShowSpark setting on every animation tick.
  if frame.latencyBar and type(_G.MSUF_PlayerCastbar_UpdateLatencyZone) == "function" then
    _G.MSUF_PlayerCastbar_UpdateLatencyZone(frame, false, duration)
  end
  if type(_G.MSUF_ApplyCastbarGlowFade) == "function" then
    _G.MSUF_ApplyCastbarGlowFade(frame, remaining, duration)
  end
  return true
end

function PA.ApplyUnitFrame(frame, index, kind)
  if PA.enabled ~= true or InCombat() or not IsVisible(frame) then return false end
  local state = PA.FrameState(frame, index, kind, frame._msufPreviewAnimState or {})
  frame._msufPreviewAnimState = state
  StoreUnitFrameRestore(frame)

  local hpMax = 1000000
  local hp = floor(hpMax * (state.hpPct or 0.7) + 0.5)
  local powerMax = 240000
  local power = floor(powerMax * (state.powerPct or 0.75) + 0.5)

  SetBar(frame.hpBar or frame.Health or frame.health, hp, hpMax, true)
  SetBar(frame.targetPowerBar or frame.powerBar or frame.Power or frame.power, power, powerMax, true)
  ApplyPrediction(frame, hpMax, state)
  ApplyPreviewName(frame, kind)
  ApplyText(frame, hp, hpMax, power, powerMax, state.hpPct, state.powerPct)
  ApplyStatus(frame, state)
  return true
end

local function PreviewFrame(unit)
  return CoreFrame(unit) or _G["MSUF_" .. unit]
end

local function RefreshUnitPreviewFrames()
  if not (_G.MSUF_PreviewTestMode == true and EditModePreviewActive()) then return false end
  local any = false
  for i = 1, #PREVIEW_UNITS do
    local unit = PREVIEW_UNITS[i]
    local frame = PreviewFrame(unit)
    any = PA.ApplyUnitFrame(frame, i, unit) or any
  end
  return any
end

local function RefreshBossPreviewFrames()
  if not BossPreviewActive() then return false end
  local any = false
  for i = 1, #BOSS_UNITS do
    local unit = BOSS_UNITS[i]
    local frame = PreviewFrame(unit)
    any = PA.ApplyUnitFrame(frame, i, "boss") or any
  end
  return any
end

local function BossCastbarPreview(index)
  if index == 1 then return _G.MSUF_BossCastbarPreview or _G.MSUF_BossCastbarPreview1 end
  return _G["MSUF_BossCastbarPreview" .. index]
end

local function RefreshCastbarPreviewFrames()
  if not (EditModePreviewActive() or BossPreviewActive()) then return false end
  local any = false
  for i = 1, #CASTBAR_PREVIEWS do
    local spec = CASTBAR_PREVIEWS[i]
    any = ApplyCastbarPreviewFrame(_G[spec.name], i + 20, spec.unit, spec.label) or any
  end

  local bossMax = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or #BOSS_UNITS
  if bossMax < 1 then bossMax = #BOSS_UNITS elseif bossMax > 12 then bossMax = 12 end
  for i = 1, bossMax do
    any = ApplyCastbarPreviewFrame(BossCastbarPreview(i), i + 30, "boss", "Celestial Ruin") or any
  end
  return any
end

local function RestoreCastbarPreviewFrames()
  for i = 1, #CASTBAR_PREVIEWS do
    RestoreCastbarFrame(_G[CASTBAR_PREVIEWS[i].name])
  end
  local bossMax = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or #BOSS_UNITS
  if bossMax < 1 then bossMax = #BOSS_UNITS elseif bossMax > 12 then bossMax = 12 end
  for i = 1, bossMax do
    RestoreCastbarFrame(BossCastbarPreview(i))
  end
end

local function RefreshStaticCastbarPreviews()
  if EditModeAnimationTargetActive() and type(_G.MSUF_UpdatePlayerCastbarPreview) == "function" then
    _G.MSUF_UpdatePlayerCastbarPreview()
    return
  end
  if BossPreviewActive() and type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
    _G.MSUF_UpdateBossCastbarPreview()
  end
end

local function RefreshMenuBoxes()
  local preview = MSUF and (MSUF.UFPreview or MSUF.MSUF_UFPreview) or _G.MSUF_UFPreview
  local refresh = preview and preview.Refresh
  if type(refresh) ~= "function" then return false end
  local any = false
  for box in pairs(PA.menuBoxes) do
    if IsVisible(box) then
      refresh(box, "PREVIEW_COMBAT_ANIMATE")
      any = true
    end
  end
  return any
end

local function RefreshGroupBoxes()
  local any = false
  for box in pairs(PA.groupBoxes) do
    if IsVisible(box) then
      if type(box.RequestRefresh) == "function" then
        box:RequestRefresh("GROUP_PREVIEW_COMBAT_ANIMATE")
      elseif type(box.Refresh) == "function" then
        box:Refresh("GROUP_PREVIEW_COMBAT_ANIMATE")
      end
      any = true
    end
  end
  return any
end

local function RefreshGroupPreviews()
  local fn = _G.MSUF_GF_RefreshPreviewAnimation
  if type(fn) == "function" then
    return fn() == true
  end
  return false
end

local function RefreshGroupRuntimeFrames()
  if not (PA.source == "edit_mode" and EditModePreviewActive()) then return false end
  if type(_G.MSUF_GF_EM2_IsPreviewShown) == "function" and _G.MSUF_GF_EM2_IsPreviewShown() ~= true then return false end
  local gf = MSUF and MSUF.GF
  local each = gf and gf.ForEachFrame
  if type(each) ~= "function" then return false end
  local any = false
  local index = 0
  each(function(frame)
    if frame and frame._msufGFIsPreviewFrame ~= true and IsVisible(frame) then
      index = index + 1
      any = PA.ApplyUnitFrame(frame, index, frame._msufGFKind or "group") or any
    end
  end, false)
  return any
end

local function RefreshStaticGroupRuntimeFrames()
  local refresh = _G.MSUF_GF_RefreshVisuals
  if type(refresh) == "function" then
    refresh(nil, MSUF and MSUF.GF and MSUF.GF.DIRTY_VISUAL)
    return
  end
  local gf = MSUF and MSUF.GF
  if gf and type(gf.RefreshVisuals) == "function" then
    gf.RefreshVisuals(nil, gf.DIRTY_VISUAL)
  end
end

local function RefreshEditAuraPreviews()
  if not EditModePreviewActive() then return false end
  local a3 = MSUF and MSUF.MSUF_Auras3
  local refresh = a3 and a3.RefreshEditPreview
  if type(refresh) == "function" then
    refresh()
    return true
  end
  return false
end

local function RefreshEditModeTargets()
  if not EditModeAnimationTargetActive() then return false end
  local any = false
  any = RefreshGroupPreviews() or any
  any = RefreshGroupRuntimeFrames() or any
  any = RefreshUnitPreviewFrames() or any
  any = RefreshBossPreviewFrames() or any
  any = RefreshEditAuraPreviews() or any
  any = RefreshCastbarPreviewFrames() or any
  return any
end

local function RefreshPreviewTargets()
  local any = false
  any = RefreshMenuBoxes() or any
  any = RefreshGroupBoxes() or any
  any = RefreshGroupPreviews() or any
  any = RefreshBossPreviewFrames() or any
  any = RefreshCastbarPreviewFrames() or any
  return any
end

local StopDriver

local function RefreshAfterDriverStop(stoppedSource)
  RefreshStaticCastbarPreviews()
  RefreshMenuBoxes()
  RefreshGroupBoxes()
  RefreshGroupPreviews()
  if stoppedSource == "edit_mode" then
    RefreshStaticGroupRuntimeFrames()
  end
  RefreshEditAuraPreviews()
  if _G.MSUF_EM2_ReforcePreviewFrames then
    _G.MSUF_EM2_ReforcePreviewFrames()
  end
  if BossPreviewActive() and _G.MSUF_SyncBossUnitframePreviewWithUnitEdit then
    _G.MSUF_SyncBossUnitframePreviewWithUnitEdit()
  end
end

RegisterEditModeStopListener = function()
  if editModeStopListenerRegistered then return end
  local register = _G.MSUF_RegisterAnyEditModeListener
  if type(register) ~= "function" then return end
  editModeStopListenerRegistered = true
  register(function(active)
    if active == true then return end
    if PA.enabled == true and PA.source == "edit_mode" then
      StopDriver(true)
    end
  end)
end

local function AnimationOnUpdate(_, elapsed)
  if PA.enabled ~= true then
    StopDriver(true)
    return
  end
  if InCombat() then
    StopDriver(true, true)
    return
  end
  elapsed = tonumber(elapsed) or 0
  PA.elapsed = (tonumber(PA.elapsed) or 0) + elapsed
  PA._accum = (tonumber(PA._accum) or 0) + elapsed
  if PA._accum < UPDATE_INTERVAL then return end
  PA._accum = 0

  if not HasVisibleTarget() then
    noTargetElapsed = noTargetElapsed + UPDATE_INTERVAL
    if noTargetElapsed >= NO_TARGET_GRACE then
      StopDriver(true)
    end
    return
  end
  noTargetElapsed = 0

  local any = PA.source == "edit_mode" and RefreshEditModeTargets() or RefreshPreviewTargets()
  if not any then
    noTargetElapsed = noTargetElapsed + UPDATE_INTERVAL
    if noTargetElapsed >= NO_TARGET_GRACE then StopDriver(true) end
  end
end

local function EnsureDriver()
  if driver then return driver end
  driver = CreateFrame("Frame", "MSUF_PreviewAnimationDriver")
  driver:Hide()
  driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
      StopDriver(true, true)
    end
  end)
  return driver
end

local function StartDriver()
  if PA.enabled ~= true or InCombat() then return false end
  local f = EnsureDriver()
  noTargetElapsed = 0
  PA._accum = 0
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:SetScript("OnUpdate", AnimationOnUpdate)
  f:Show()
  NotifyRefreshOwners()
  AnimationOnUpdate(f, UPDATE_INTERVAL)
  return PA.enabled == true
end

StopDriver = function(clearEnabled, forceCombatStop)
  local stoppedSource = PA.source
  local stoppedInCombat = forceCombatStop == true or InCombat()
  local combatEditModeStop = stoppedSource == "edit_mode" and stoppedInCombat == true
  if driver then
    driver:SetScript("OnUpdate", nil)
    driver:UnregisterEvent("PLAYER_REGEN_DISABLED")
    driver:Hide()
  end
  PA._accum = 0
  noTargetElapsed = 0
  if clearEnabled ~= false then
    PA.enabled = false
    PA.source = nil
  end
  if combatEditModeStop then
    ClearEditModePreviewFlags()
  end
  RestoreCastbarPreviewFrames()
  RestoreUnitAnimationFrames(combatEditModeStop)
  if clearEnabled ~= false then
    if not stoppedInCombat then
      RefreshAfterDriverStop(stoppedSource)
    end
  end
  NotifyRefreshOwners()
end

function PA.SetEnabled(enabled, source)
  enabled = enabled == true
  if enabled and InCombat() then
    StopDriver(true, true)
    return false, "combat"
  end
  if enabled and PA.enabled == true and source and PA.source ~= source then
    StopDriver(false)
  end
  PA.enabled = enabled
  PA.source = enabled and source or nil
  if enabled then
    PA.elapsed = 0
    if source == "edit_mode" then
      PrepareEditModePreviewForAnimation()
    end
    if not StartDriver() then
      PA.enabled = false
      NotifyRefreshOwners()
      return false, "unavailable"
    end
  else
    StopDriver(true)
  end
  return true
end

function PA.Toggle(source)
  if PA.enabled == true and source and PA.source ~= source then
    return PA.SetEnabled(true, source)
  end
  return PA.SetEnabled(PA.enabled ~= true, source)
end

ExportPublic("MSUF_PreviewAnimation", PA)
ExportPublic("MSUF_IsPreviewAnimationEnabled", function() return PA.IsEnabled() end)
ExportPublic("MSUF_SetPreviewAnimationEnabled", function(enabled, source) return PA.SetEnabled(enabled, source) end)
ExportPublic("MSUF_TogglePreviewAnimation", function(source) return PA.Toggle(source) end)
ExportPublic("MSUF_RegisterPreviewAnimationMenuBox", function(box) return PA.RegisterMenuBox(box) end)
ExportPublic("MSUF_UnregisterPreviewAnimationMenuBox", function(box) return PA.UnregisterMenuBox(box) end)
ExportPublic("MSUF_RegisterPreviewAnimationGroupBox", function(box) return PA.RegisterGroupBox(box) end)
ExportPublic("MSUF_UnregisterPreviewAnimationGroupBox", function(box) return PA.UnregisterGroupBox(box) end)
ExportPublic("MSUF_RegisterPreviewAnimationRefreshOwner", function(owner, fn) return PA.RegisterRefreshOwner(owner, fn) end)
ExportPublic("MSUF_UnregisterPreviewAnimationRefreshOwner", function(owner) return PA.UnregisterRefreshOwner(owner) end)
ExportPublic("MSUF_BuildPreviewAnimationFrameState", function(frame, index, kind, scratch, elapsed) return PA.BuildFrameState(frame, index, kind, scratch, elapsed) end)
ExportPublic("MSUF_BuildPreviewAnimationAuraState", function(kind, index, scratch, options, elapsed) return PA.BuildAuraState(kind, index, scratch, options, elapsed) end)
ExportPublic("MSUF_GetPreviewAnimationFrameState", function(frame, index, kind, scratch) return PA.FrameState(frame, index, kind, scratch) end)
ExportPublic("MSUF_GetPreviewAnimationAuraState", function(kind, index, scratch, options) return PA.AuraState(kind, index, scratch, options) end)
