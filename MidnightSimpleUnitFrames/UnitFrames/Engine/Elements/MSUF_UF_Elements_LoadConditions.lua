-- UF load-condition element: applies profile visibility rules to unit frames.
-- Protected visibility or secure state changes must stay behind combat-safe helpers.
local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local UF = MSUF.UF
if not UF then return end

-- Unitframe load-condition element.
-- Owns secure state-driver visibility rules for mounted/combat/group/instance/resting style
-- conditions. Protected state changes are deferred or expressed through secure snippets.
local RegisterStateDriver = _G.RegisterStateDriver
local UnregisterStateDriver = _G.UnregisterStateDriver
local SecureCmdOptionParse = _G.SecureCmdOptionParse
local InCombatLockdown = _G.InCombatLockdown
local UnitAffectingCombat = _G.UnitAffectingCombat
local IsInInstance = _G.IsInInstance
local C_Housing = _G.C_Housing
local Secrets = MSUF.Secrets or {}
local UnitExistsPlain = Secrets.UnitExistsPlain or function(_) return true end
local type = type
local tonumber = tonumber

local EMPTY_EVENTS = {}
local FALLBACK_EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "PLAYER_MOUNT_DISPLAY_CHANGED",
  "UNIT_ENTERED_VEHICLE",
  "UNIT_EXITED_VEHICLE",
  "PLAYER_UPDATE_RESTING",
  "GROUP_ROSTER_UPDATE",
  "UPDATE_STEALTH",
  "ZONE_CHANGED_NEW_AREA",
}
local PREVIEW_UNITS = {
  target = true,
  focus = true,
  targettarget = true,
  focustarget = true,
  pet = true,
}
local BOSS_PREVIEW_UNITS = {
  boss1 = true,
  boss2 = true,
  boss3 = true,
  boss4 = true,
  boss5 = true,
}
local BOSS_PREVIEW_REFRESH_ELEMENTS = {
  "Alpha",
  "Health",
  "Power",
  "Text",
  "NameText",
  "HealthText",
  "PowerText",
  "Portrait",
  "Borders",
}

local LoadConditions = {}
local bossPreviewAppliedActive
local bossPreviewCombatCleanupPending
local BOSS_PREVIEW_LIGHT_REASONS = {
  MSUF_BOSS_PREVIEW = true,
  MSUF_BOSS_PREVIEW_SYNC = true,
  MSUF_BOSS_PREVIEW_OFF = true,
  MSUF2_BOSS_PAGE_CORE = true,
  MSUF2_BOSS_PAGE_FALLBACK = true,
}

local function BossPreviewCombatLocked()
  return (InCombatLockdown and InCombatLockdown())
    or (UnitAffectingCombat and UnitAffectingCombat("player"))
    or _G.MSUF_InCombat == true
end

local function InInstance()
  if not IsInInstance then
    return false
  end
  local inside = IsInInstance()
  return inside == true or inside == 1
end

local function InHousing()
  local fn = C_Housing and C_Housing.IsInsideHouseOrPlot
  if type(fn) ~= "function" then
    return false
  end
  return fn() == true
end

local function ShouldForcePreview(frame)
  if not frame then
    return false
  end
  local unit = frame.MSUFUnitKey
  if PREVIEW_UNITS[unit] == true then
    return _G.MSUF_PreviewTestMode == true
  end
  if BOSS_PREVIEW_UNITS[unit] == true then
    return _G.MSUF_BossTestMode == true
      or _G.MSUF2_BossUnitframePreviewActive == true
      or _G.MSUF_PreviewTestMode == true
  end
  return false
end

local function BuildRuntimeVisibility(frame, spec)
  local load = spec.load
  if load and load.hideInInstance == true and InInstance() then
    return "hide"
  end
  if load and load.hideInHousing == true and InHousing() then
    return "hide"
  end

  local unit = spec.unit or frame.MSUFUnitKey
  if type(unit) ~= "string" or unit == "" then
    unit = "player"
  end

  local rules = frame._msufLoadRules
  if not rules then
    rules = {}
    frame._msufLoadRules = rules
  end
  local n = 0
  if load then
    if load.hideMounted == true then n = n + 1; rules[n] = "[mounted] hide" end
    if load.hideInVehicle == true then
      n = n + 1; rules[n] = "[@player,unithasvehicleui] hide"
      n = n + 1; rules[n] = "[vehicleui] hide"
    end
    if load.hideResting == true then n = n + 1; rules[n] = "[resting] hide" end
    if load.hideInCombat == true then n = n + 1; rules[n] = "[combat] hide" end
    if load.hideOutOfCombat == true then n = n + 1; rules[n] = "[nocombat] hide" end
    if load.hideNoTarget == true then n = n + 1; rules[n] = "[@target,noexists] hide" end
    if load.hideOutOfCombatNoTarget == true then n = n + 1; rules[n] = "[nocombat,@target,noexists] hide" end
    if load.hideStealthed == true then n = n + 1; rules[n] = "[stealth] hide" end
    if load.hideSolo == true then n = n + 1; rules[n] = "[nogroup] hide" end
    if load.hideInGroup == true then n = n + 1; rules[n] = "[group] hide" end
  end
  n = n + 1
  rules[n] = "[@" .. unit .. ",exists] show"
  n = n + 1
  rules[n] = "hide"
  for i = n + 1, #rules do
    rules[i] = nil
  end
  return table.concat(rules, "; ")
end

local function BuildVisibility(frame, spec)
  if not (frame and spec) or spec.enabled == false then
    return "hide"
  end

  local visibility = BuildRuntimeVisibility(frame, spec)
  if ShouldForcePreview(frame) then
    -- Preview must not stay force-shown when combat starts. The secure driver
    -- falls back to normal runtime visibility in combat without Lua work.
    return "[nocombat] show; " .. visibility
  end
  return visibility
end

local RegisterUnitWatch = _G.RegisterUnitWatch
local UnregisterUnitWatch = _G.UnregisterUnitWatch
local UnitWatchRegistered = _G.UnitWatchRegistered

-- A frame with no load conditions resolves to "[@unit,exists] show; hide",
-- which is exactly what RegisterUnitWatch does natively -- and far cheaper.
-- Stacking a RegisterStateDriver("visibility") on top makes the secure
-- macro-conditional engine re-evaluate that expression on state changes
-- (including target changes for @target-relative frames). That secure
-- evaluation is billed to MSUF and was the per-click profiler spike that no
-- Lua probe could see.
-- So: only install the state driver when there is REAL conditional work;
-- otherwise hand visibility to RegisterUnitWatch.
local function VisibilityNeedsDriver(spec)
  local load = spec and spec.load
  if load and load.active == true then
    return true
  end
  if load and load.hideInInstance == true then
    return true
  end
  if load and load.hideInHousing == true then
    return true
  end
  return false
end

-- Existence-only visibility is structural frame ownership, not an active
-- LoadConditions feature. Factory/SecureGroupHeader keep the native unit watch
-- alive, while this element enters Core routing only for real conditional
-- visibility or a forced unit-frame preview.
function LoadConditions.IsEnabled(frame, spec)
  return VisibilityNeedsDriver(spec) or ShouldForcePreview(frame)
end

local function VisibilityFrame(frame)
  return frame
end

local function RegisterVisibility(frame, spec)
  local visibilityFrame = VisibilityFrame(frame)
  if UnitWatchRegistered then
    frame._msufUnitWatched = UnitWatchRegistered(visibilityFrame) == true and true or nil
  end
  -- Existence-only visibility: use the lightweight unit watch, never a secure
  -- state driver. Tear down any driver left from a previous conditional config.
  if not VisibilityNeedsDriver(spec) and not ShouldForcePreview(frame) and RegisterUnitWatch then
    if InCombatLockdown and InCombatLockdown() then
      -- Combat: don't touch secure registration. If a driver is currently
      -- installed we must defer the swap-out; otherwise the unit watch from
      -- spawn already covers us and there is nothing to do.
      if frame._msufVisibilityExpr ~= nil then
        UF.MarkDirty(frame.MSUFUnitKey)
        if UF.Factory and UF.Factory.EnsureDeferredDriver then
          UF.Factory.EnsureDeferredDriver()
        end
        return false
      end
    elseif frame._msufVisibilityExpr ~= nil then
      if UnregisterStateDriver then
        UnregisterStateDriver(visibilityFrame, "visibility")
      end
      frame._msufVisibilityExpr = nil
    end
    if frame._msufUnitWatched ~= true then
      RegisterUnitWatch(visibilityFrame)
      frame._msufUnitWatched = true
    end
    frame._msufVisibilityManaged = nil
    return true
  end

  local visibility = BuildVisibility(frame, spec)
  frame._msufVisibilityManaged = true
  if RegisterStateDriver then
    if frame._msufVisibilityExpr ~= visibility then
      if InCombatLockdown and InCombatLockdown() then
        UF.MarkDirty(frame.MSUFUnitKey)
        if UF.Factory and UF.Factory.EnsureDeferredDriver then
          UF.Factory.EnsureDeferredDriver()
        end
        return false
      end
      -- Swapping from unit-watch to driver: the watch and the driver both
      -- manage visibility, so drop the watch first to avoid double control.
      if frame._msufUnitWatched == true then
        UnregisterUnitWatch(visibilityFrame)
        frame._msufUnitWatched = nil
      end
      RegisterStateDriver(visibilityFrame, "visibility", visibility)
      frame._msufVisibilityExpr = visibility
    end
    return true
  end

  local show = visibility == "show"
  if visibility ~= "hide" and SecureCmdOptionParse then
    show = SecureCmdOptionParse(visibility) == "show"
  elseif visibility ~= "hide" then
    show = UnitExistsPlain(frame.MSUFUnitKey)
  end
  if frame._msufLoadShown ~= show then
    visibilityFrame:SetShown(show)
    frame._msufLoadShown = show
  end
  return true
end

function LoadConditions.GetUnitlessEvents(frame, spec)
  local load = spec and spec.load
  if not load or load.active ~= true then
    return EMPTY_EVENTS
  end
  if not RegisterStateDriver then
    return FALLBACK_EVENTS
  end
  return load.unitlessEvents or EMPTY_EVENTS
end

function LoadConditions.Apply(frame, spec)
  RegisterVisibility(frame, spec)
end

function LoadConditions.Update(frame, event)
  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    -- Instance/housing checks are resolved into the visibility expression, so
    -- these zone boundaries must rebuild it. RegisterVisibility already defers
    -- protected changes when combat lockdown makes that necessary.
    return RegisterVisibility(frame, frame and frame.MSUFSpec)
  end
  -- Identity refreshes (target/focus swap) call this on every unit change, but a
  -- unit swap NEVER changes the visibility expression: BuildRuntimeVisibility
  -- depends only on the spec (load rules + the frame's fixed unit token like
  -- "target"), not on which GUID is currently targeted. The secure state driver
  -- was already registered at Apply and re-evaluates itself natively in the
  -- engine on the conditions that matter (combat/resting/instance/exists). So
  -- re-running RegisterVisibility here just rebuilds an identical string and
  -- throws it away -- pure per-swap waste (this was a large chunk of the
  -- target-swap cost). Skip once the driver/watch is installed; a real config
  -- change goes through LoadConditions.Apply / UF.RefreshVisibilityDrivers,
  -- which call RegisterVisibility directly and are not gated by this.
  if frame and (frame._msufVisibilityExpr ~= nil or frame._msufUnitWatched == true) then
    return
  end
  RegisterVisibility(frame, frame and frame.MSUFSpec)
end

function LoadConditions.Disable(frame)
  if not frame then
    return
  end
  if UnregisterStateDriver and InCombatLockdown and InCombatLockdown() then
    UF.MarkDirty(frame.MSUFUnitKey)
    if UF.Factory and UF.Factory.EnsureDeferredDriver then
      UF.Factory.EnsureDeferredDriver()
    end
    return false
  end
  frame._msufVisibilityManaged = nil
  frame._msufVisibilityExpr = nil
  if UnregisterStateDriver then
    UnregisterStateDriver(frame, "visibility")
  end
  -- A conditional driver replaces RegisterUnitWatch while active. Restore the
  -- native existence owner immediately when the last condition is removed;
  -- targeted RefreshElements calls do not pass through Factory's post-apply
  -- fallback that normally performs this hand-off for fresh single frames.
  if RegisterUnitWatch and not (frame.MSUFSpec and frame.MSUFSpec.enabled == false) then
    local watched = UnitWatchRegistered and UnitWatchRegistered(frame) == true
    if not watched then
      RegisterUnitWatch(frame)
    end
    frame._msufUnitWatched = true
  end
  return true
end

UF.RegisterElement("LoadConditions", LoadConditions)

function UF.RefreshVisibilityDrivers(unit)
  return UF.RefreshElements(unit, { "LoadConditions" }, "MSUF_LOAD_CONDITIONS")
end

local function MSUF_RefreshAllUnitVisibilityDrivers()
  return UF.RefreshVisibilityDrivers(nil)
end
ExportPublic("MSUF_RefreshAllUnitVisibilityDrivers", MSUF_RefreshAllUnitVisibilityDrivers)

local function SetShown(frame, shown)
  if not frame then
    return
  end
  if frame.SetShown then
    frame:SetShown(shown == true)
  elseif shown then
    frame:Show()
  else
    frame:Hide()
  end
end

local function ResolveBossPreviewHealthColor(frame, pct)
  local spec = frame and frame.MSUFSpec
  local health = spec and spec.health or {}
  local mode = health.mode
  local alpha = tonumber(health.alpha or health.a) or 1
  if mode == "dark" or mode == "unified" then
    return health.r or 1, health.g or 1, health.b or 1, alpha
  elseif mode == "gradient" then
    local common = MSUF and MSUF.UFBarTextCommon
    local resolveGradient = common and common.PreviewHealthGradientColor
    if type(resolveGradient) == "function" then
      local r, g, b = resolveGradient(health, pct)
      if r ~= nil then return r, g, b, 1 end
    end
  end

  -- A synthetic boss has no live UnitReaction/UnitClassification result. Use
  -- the same deterministic hostile identity that runtime resolves for a live
  -- boss, while honoring the optional NPC-type coloring mode.
  local kind = "enemy"
  if health.npcColorMode == "type"
    and health.npcTypeColorBar ~= false
    and health.npcTypeBoss ~= false then
    kind = "npcBoss"
  end
  local common = MSUF and MSUF.UFBarTextCommon
  local resolveNPC = common and common.NPCColor
  if type(resolveNPC) == "function" then
    local r, g, b = resolveNPC(kind)
    if r ~= nil then return r, g, b, 1 end
  end
  if kind == "npcBoss" then return 0.74, 0.11, 0, 1 end
  return 0.85, 0.10, 0.10, 1
end
UF.ResolveBossPreviewHealthColor = ResolveBossPreviewHealthColor

local function SetBarPreview(bar, value, maxValue, r, g, b, a)
  if not bar then
    return
  end
  if bar.SetMinMaxValues then
    bar:SetMinMaxValues(0, maxValue)
  end
  if bar.SetValue then
    bar:SetValue(value)
  end
  if bar.SetStatusBarColor then
    bar:SetStatusBarColor(r, g, b, a or 1)
    -- Runtime color writers cache both the configured and resolved colors.
    -- Preview writes are temporary, so invalidate both caches to guarantee the
    -- live unit color is restored when the preview is switched off.
    bar._msufR, bar._msufG, bar._msufB, bar._msufA = nil, nil, nil, nil
    bar._msufStatusR, bar._msufStatusG, bar._msufStatusB, bar._msufStatusA = nil, nil, nil, nil
  end
  if bar.SetAlpha then
    bar:SetAlpha(1)
  end
  local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
  if fill and fill.SetAlpha then
    -- A missing boss can leave the health-only range/alpha lane at zero. The
    -- synthetic preview must explicitly make that fill visible, otherwise its
    -- correct red RGB is present but the frame still appears black.
    fill:SetAlpha(1)
    fill._msufAlphaHealth = nil
    fill._msufAlphaStatusTexture = nil
  end
  SetShown(bar, true)
end

local function BossPreviewPercent(unit)
  return unit == "boss1" and 55 or 72
end

local function BossPreviewPowerPercent()
  return 100
end

local function BossLiveUnitExists(unit)
  return UnitExistsPlain(unit) == true
end

local function BossPreviewConfigDirty()
  return UF.Config and UF.Config.dirty == true
end

local function ApplyBossPreviewText(frame, hp, hpMax, power, powerMax)
  if not frame then
    return
  end
  if frame.nameText then
    frame.nameText:SetText("Boss Preview")
    SetShown(frame.nameText, true)
  end
  if frame.levelText then
    frame.levelText:SetText("??")
    SetShown(frame.levelText, true)
  end

  local text = MSUF and MSUF.UFText
  local rt = frame._msufTextRuntime
  if not (text and text.UpdateTextSlots and rt) then
    return
  end
  rt.healthMissing = nil
  text.UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.MSUFUnitKey, BossPreviewPercent, rt.healthNeedsPercent, rt)

  text.UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.MSUFUnitKey, BossPreviewPowerPercent, rt.powerNeedsPercent, rt)
end

local function ApplyBossPreviewFrameData(frame, index)
  if not frame then
    return
  end
  index = tonumber(index) or 1
  local hpMax = 1000000
  local hp = index == 1 and 550000 or 720000
  local powerMax = 240000
  local power = powerMax

  frame._msufBossPreviewForced = true
  local state = frame._msufUnitState
  if type(state) == "table" then
    state.exists = true
    state.existsKnown = true
    state.dead = false
    state.connected = true
    state.npcKind = "npcBoss"
    state.npcKindKnown = true
  end

  local r, g, b, a = ResolveBossPreviewHealthColor(frame, hp / hpMax)
  SetBarPreview(frame.hpBar or frame.Health, hp, hpMax, r, g, b, a)
  frame._msufAlphaLastHP = nil
  SetBarPreview(frame.targetPowerBar or frame.powerBar or frame.Power, power, powerMax, 0.05, 0.64, 0.92)
  ApplyBossPreviewText(frame, hp, hpMax, power, powerMax)
end

local function InvalidateBossPreviewBar(bar, restoreFill)
  if not bar then return end
  bar._msufR, bar._msufG, bar._msufB, bar._msufA = nil, nil, nil, nil
  bar._msufStatusR, bar._msufStatusG, bar._msufStatusB, bar._msufStatusA = nil, nil, nil, nil
  local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
  if fill then
    fill._msufAlphaHealth = nil
    fill._msufAlphaStatusTexture = nil
    if restoreFill and fill.SetAlpha then fill:SetAlpha(1) end
  end
  if restoreFill and bar.SetAlpha then bar:SetAlpha(1) end
end

-- Preview data is written into the real boss unit buttons. Combat lockdown
-- prevents the normal full visibility/runtime rebuild, so strip only the
-- synthetic Lua state and restore visual lanes here; protected Show/Hide and
-- state-driver work remains deferred until combat ends.
local function ClearBossPreviewFrameForRuntime(frame, restoreVisuals)
  if not frame or frame._msufBossPreviewForced ~= true then return false end
  frame._msufBossPreviewForced = nil
  frame._msufUnitState = nil
  frame._msufAlphaLastFrame = nil
  frame._msufAlphaLastHP = nil
  frame._msufAlphaLastFG = nil

  local healthBar = frame.hpBar or frame.Health
  InvalidateBossPreviewBar(healthBar, restoreVisuals)
  InvalidateBossPreviewBar(frame.targetPowerBar or frame.powerBar or frame.Power, restoreVisuals)

  if restoreVisuals then
    -- The range driver has its own last-result cache. Invalidate it before the
    -- temporary in-range handoff so its next real boss result is never skipped.
    frame._msufRangeInRange = nil
    frame._msufRangeMulApplied = nil
    local applyRange = UF.ApplyRangeModifier or _G.MSUF_UF_ApplyRangeModifier
    if type(applyRange) == "function" then
      applyRange(frame, 1, true)
    end
    local unit = frame.MSUFUnitKey
    local refreshColor = _G.MSUF_UFCore_RefreshHealthBarColor
    if BossLiveUnitExists(unit) and type(refreshColor) == "function" then
      refreshColor(frame, "MSUF_BOSS_PREVIEW_HANDOFF")
    end
  end
  return true
end

local function ClearBossPreviewFramesForCombat()
  _G.MSUF2_BossUnitframePreviewActive = nil
  local cleared = false
  for i = 1, 5 do
    local frame = UF.frames and UF.frames["boss" .. i]
    if ClearBossPreviewFrameForRuntime(frame, true) then cleared = true end
  end
  if cleared then bossPreviewCombatCleanupPending = true end
  return cleared
end
UF.ClearBossPreviewFramesForCombat = ClearBossPreviewFramesForCombat
ExportPublic("MSUF_ClearBossUnitframePreviewForCombat", ClearBossPreviewFramesForCombat)

local function ApplyBossPreviewFrames(active)
  for i = 1, 5 do
    local frame = UF.frames and UF.frames["boss" .. i]
    local unit = "boss" .. i
    if frame and active and not BossLiveUnitExists(unit) then
      frame:Show()
      if frame.SetAlpha then frame:SetAlpha(1) end
      if frame.EnableMouse then frame:EnableMouse(true) end
      ApplyBossPreviewFrameData(frame, i)
    elseif frame then
      ClearBossPreviewFrameForRuntime(frame, true)
    end
  end
end

local function BossPreviewFramesReady(active)
  local frames = UF.frames
  if type(frames) ~= "table" then
    return false
  end
  local sawFrame = false
  for i = 1, 5 do
    local frame = frames["boss" .. i]
    if frame then
      sawFrame = true
      if active then
        if frame._msufBossPreviewForced ~= true then return false end
        if frame.IsShown and not frame:IsShown() then return false end
      elseif frame._msufBossPreviewForced == true then
        return false
      end
    end
  end
  return sawFrame
end

local function CanUseLightBossPreviewApply(active, reason)
  if bossPreviewCombatCleanupPending == true then
    return false
  end
  if bossPreviewAppliedActive ~= active then
    return false
  end
  if BossPreviewConfigDirty() then
    return false
  end
  if BOSS_PREVIEW_LIGHT_REASONS[reason or ""] ~= true then
    return false
  end
  return BossPreviewFramesReady(active)
end

local function RefreshBossAuras()
  local A3 = MSUF and MSUF.MSUF_Auras3
  if A3 and type(A3.RequestScope) == "function" then
    A3.RequestScope("boss", "MSUF_BOSS_PREVIEW")
    return
  end
  if A3 and type(A3.RequestUnit) == "function" then
    A3.RequestUnit("boss")
    return
  end
  if A3 and type(A3.RefreshUnit) == "function" then
    for i = 1, 5 do
      A3.RefreshUnit("boss" .. i)
    end
    return
  end
  if A3 and type(A3.RefreshAll) == "function" then
    A3.RefreshAll()
  end
end

function UF.ApplyBossPreviewState(active, reason)
  active = active == true
  if BossPreviewCombatLocked() then
    ClearBossPreviewFramesForCombat()
    return false
  end

  local refreshReason = reason or "MSUF_BOSS_PREVIEW"
  if CanUseLightBossPreviewApply(active, refreshReason) then
    ApplyBossPreviewFrames(active)
    return true
  end

  -- Seed the synthetic identity and make missing boss frames visible before
  -- structural elements are refreshed. Portrait.Apply otherwise sees a hidden,
  -- unitless frame and defers the image to an OnShow transition which a secure
  -- preview visibility handoff does not always produce.
  ApplyBossPreviewFrames(active)
  UF.RefreshVisibilityDrivers("boss")
  if active and type(UF.RefreshElements) == "function" then
    UF.RefreshElements("boss", BOSS_PREVIEW_REFRESH_ELEMENTS, refreshReason)
  elseif type(UF.RefreshElements) == "function" then
    UF.RefreshElements("boss", BOSS_PREVIEW_REFRESH_ELEMENTS, refreshReason)
  end
  UF.UpdateRuntime("boss", refreshReason)

  if active then
    ApplyBossPreviewFrames(true)
  end
  RefreshBossAuras()
  if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
    _G.MSUF_UpdateBossCastbarPreview()
  end
  local em2 = _G.MSUF_EM2
  if em2 and em2.Movers and type(em2.Movers.SyncAll) == "function" then
    em2.Movers.SyncAll()
  end
  bossPreviewAppliedActive = active
  bossPreviewCombatCleanupPending = nil
  return true
end

local function MSUF_ApplyBossUnitframePreviewState(active, reason)
  if BossPreviewCombatLocked() then
    ClearBossPreviewFramesForCombat()
    return false
  end
  _G.MSUF2_BossUnitframePreviewActive = active == true and true or nil
  return UF.ApplyBossPreviewState(active, reason or "MSUF_BOSS_PREVIEW")
end
ExportPublic("MSUF_ApplyBossUnitframePreviewState", MSUF_ApplyBossUnitframePreviewState)

local function MSUF_SyncBossUnitframePreviewWithUnitEdit()
  if BossPreviewCombatLocked() then
    ClearBossPreviewFramesForCombat()
    return false
  end
  local editActive = _G.MSUF_UnitEditModeActive == true
  local active = _G.MSUF2_BossUnitframePreviewActive == true
    or (_G.MSUF_BossTestMode == true and editActive)
    or (_G.MSUF_PreviewTestMode == true and editActive)
  return UF.ApplyBossPreviewState(active, active and "MSUF_BOSS_PREVIEW_SYNC" or "MSUF_BOSS_PREVIEW_OFF")
end
ExportPublic("MSUF_SyncBossUnitframePreviewWithUnitEdit", MSUF_SyncBossUnitframePreviewWithUnitEdit)
