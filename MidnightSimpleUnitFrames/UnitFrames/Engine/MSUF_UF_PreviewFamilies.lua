-- Boss and arena previews share one lifecycle; their synthetic painters remain distinct.
local _, MSUF = ...
local UF = MSUF.Require("MSUF", "UnitFrames/Engine/MSUF_UF_PreviewFamilies.lua").UF
local Preview = UF.Preview
local previewKind = type(Preview)
assert(previewKind == "table", "MSUF: missing required dependency 'UF.Preview' required by PreviewFamilies")
local validateKind = type(Preview.Validate)
assert(validateKind == "function", "MSUF: missing required dependency 'UF.Preview.Validate' required by PreviewFamilies")
Preview.Validate("UnitFrames/Engine/MSUF_UF_PreviewFamilies.lua")
local state = Preview.State
local ExportPublic = MSUF.ExportPublic
local UnitExistsPlain = MSUF.Secrets.UnitExistsPlain
local InCombatLockdown, UnitAffectingCombat = _G.InCombatLockdown, _G.UnitAffectingCombat
local type, tonumber = type, tonumber
local FILE = "UnitFrames/Engine/MSUF_UF_PreviewFamilies.lua"
local REFRESH_ELEMENTS = { "Health", "Power", "Prediction", "Text", "NameText", "HealthText", "PowerText", "Portrait", "Borders" }
local ALPHA_ELEMENTS = { "Alpha" }
local BOSS_PREVIEW_ABSORB = 125000
local LoadConditions = assert(UF.elements.LoadConditions, "MSUF: missing required dependency 'LoadConditions' required by PreviewFamilies")
local RefreshHealthAlpha = LoadConditions.UpdateHealthVisibility
local refreshKind = type(RefreshHealthAlpha)
assert(refreshKind == "function", "MSUF: missing required dependency 'LoadConditions.UpdateHealthVisibility' required by PreviewFamilies")

local function BossPreviewCombatLocked()
  return (InCombatLockdown and InCombatLockdown())
    or (UnitAffectingCombat and UnitAffectingCombat("player"))
    or _G.MSUF_InCombat == true
end

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

-- Fixed per-slot identities keep the preview deterministic across sessions.
local ARENA_PREVIEW_CLASSES = { "MAGE", "ROGUE", "PRIEST", "WARRIOR", "DRUID" }
local ARENA_PREVIEW_CLASS_FALLBACK_COLORS = {
  MAGE = { 0.25, 0.78, 0.92 },
  ROGUE = { 1, 0.96, 0.41 },
  PRIEST = { 1, 1, 1 },
  WARRIOR = { 0.78, 0.61, 0.43 },
  DRUID = { 1, 0.49, 0.04 },
}
local ARENA_PREVIEW_HP_PERCENT = { 65, 45, 80, 55, 90 }

local function ArenaPreviewClassColor(classToken)
  local getColor = _G.C_ClassColor and _G.C_ClassColor.GetClassColor
  if type(getColor) == "function" and classToken then
    local color = getColor(classToken)
    if color and color.r then
      return color.r, color.g, color.b
    end
  end
  local fallback = ARENA_PREVIEW_CLASS_FALLBACK_COLORS[classToken]
  if fallback then
    return fallback[1], fallback[2], fallback[3]
  end
  return 0.85, 0.10, 0.10
end

local function ResolvePreviewHealthColor(frame, pct, classToken)
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

  if classToken ~= nil then
    local r, g, b = ArenaPreviewClassColor(classToken)
    return r, g, b, 1
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
local ResolveBossPreviewHealthColor = ResolvePreviewHealthColor
local ResolveArenaPreviewHealthColor = ResolvePreviewHealthColor
-- Preserve the public signatures: boss ignores extra arguments; arena's absent
-- class uses its historical hostile-player fallback, never the NPC palette.
function UF.ResolveBossPreviewHealthColor(frame, pct)
  return ResolvePreviewHealthColor(frame, pct)
end
function UF.ResolveArenaPreviewHealthColor(frame, pct, classToken)
  return ResolvePreviewHealthColor(frame, pct, classToken or false)
end

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

local function ApplyBossPreviewText(frame, hp, hpMax, power, powerMax)
  if not frame then
    return
  end
  if frame.nameText then
    frame.nameText:SetText(MSUF.Translate("Boss Preview"))
    SetShown(frame.nameText, true)
  end
  if frame.levelText then
    frame.levelText:SetText("??")
    SetShown(frame.levelText, true)
    -- The preview boss is a "??" unit, so it takes the top difficulty band.
    local status = frame.MSUFSpec and frame.MSUFSpec.status
    local levelCfg = status and status.level
    local statusRuntime = MSUF and MSUF.UFStatusRuntime
    if levelCfg and levelCfg.difficultyColor == true
      and statusRuntime and statusRuntime.ApplyLevelDifficultyColor then
      statusRuntime.ApplyLevelDifficultyColor(frame.levelText, frame, nil, nil, levelCfg, 1)
    end
  end

  local text = MSUF and MSUF.UFText
  local rt = frame._msufTextRuntime
  if not (text and text.UpdateTextSlots and rt) then
    return
  end
  rt.healthMissing = nil
  rt.healthAbsorb = BOSS_PREVIEW_ABSORB
  rt._lastAbsorbTextValue = nil
  text.UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.MSUFUnitKey, BossPreviewPercent, rt.healthNeedsPercent, rt)
  if (rt.healthAbsorbSlotCount or 0) > 0 then
    text.UpdateTextSlots(rt.healthAbsorbSlots, rt.healthAbsorbSlotCount, nil, nil, frame.MSUFUnitKey, nil, false, rt)
  end

  text.UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.MSUFUnitKey, BossPreviewPowerPercent, rt.powerNeedsPercent, rt)
end

local function SeedPreviewIdentity(state)
  if type(state) ~= "table" then return false end
  state.exists, state.existsKnown = true, true
  state.dead, state.connected = false, true
  return true
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
  if UF.RefreshBossTargetPreview then UF.RefreshBossTargetPreview(frame) end
  local state = frame._msufUnitState
  if SeedPreviewIdentity(state) then
    state.npcKind = "npcBoss"
    state.npcKindKnown = true
  end

  local r, g, b, a = ResolveBossPreviewHealthColor(frame, hp / hpMax)
  SetBarPreview(frame.hpBar or frame.Health, hp, hpMax, r, g, b, a)
  frame._msufAlphaLastHP = nil
  SetBarPreview(frame.targetPowerBar or frame.powerBar or frame.Power, power, powerMax, 0.05, 0.64, 0.92)
  if UF.ApplyPredictionPreview then UF.ApplyPredictionPreview(frame, BossPreviewPercent(frame.MSUFUnitKey)) end
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

local function BuildClearFrame(forcedKey, handoffReason, boss)
  return function(frame, restoreVisuals)
    if not frame or frame[forcedKey] ~= true then return false end
    frame[forcedKey] = nil
    if boss and UF.RefreshBossTargetPreview then UF.RefreshBossTargetPreview(frame) end
    frame._msufUnitState = nil
    frame._msufAlphaLastFrame = nil
    frame._msufAlphaLastHP = nil
    frame._msufAlphaLastFG = nil
    if boss then
      if UF.ClearPredictionPreview then UF.ClearPredictionPreview(frame) end
      local rt = frame._msufTextRuntime
      if rt then rt.healthAbsorb, rt._lastAbsorbTextValue = nil, nil end
    end

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
      if UnitExistsPlain(unit) == true and type(refreshColor) == "function" then
        refreshColor(frame, handoffReason)
      end
    end
    return true
  end
end
local ClearBossPreviewFrameForRuntime = BuildClearFrame("_msufBossPreviewForced", "MSUF_BOSS_PREVIEW_HANDOFF", true)
local ClearArenaPreviewFrameForRuntime = BuildClearFrame("_msufArenaPreviewForced", "MSUF_ARENA_PREVIEW_HANDOFF", false)

local function RequestBossRangeRefresh()
  local refresh = (UF.Range and UF.Range.Refresh) or _G.MSUF_UF_RangeFade_Refresh
  if type(refresh) == "function" then
    refresh()
  end
end

local function ArenaPreviewPercent(unit)
  local index = tonumber(type(unit) == "string" and unit:match("^arena(%d+)$") or nil) or 1
  return ARENA_PREVIEW_HP_PERCENT[index] or 65
end

local function ArenaPreviewPowerPercent()
  return 100
end

local function ArenaPreviewLevelLabel()
    local cap = type(GetMaxLevelForPlayerExpansion) == "function" and tonumber(GetMaxLevelForPlayerExpansion()) or nil
    local playerCap = type(GetMaxPlayerLevel) == "function" and tonumber(GetMaxPlayerLevel()) or nil
    local maxLevel = cap and playerCap and math.min(cap, playerCap) or cap or playerCap
    return maxLevel and tostring(maxLevel) or "??"
end

local function ApplyArenaPreviewText(frame, hp, hpMax, power, powerMax, classToken)
  if not frame then
    return
  end
  if frame.nameText then
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    local label = (type(names) == "table" and names[classToken]) or MSUF.Translate("Arena Preview")
    frame.nameText:SetText(label)
    SetShown(frame.nameText, true)
  end
  if frame.levelText then
    -- Opponents are max level on every arena client: 70 on TBC, 90 on Mists
    -- and Midnight. Ask the client instead of carrying one expansion's cap,
    -- the way GameRulesUtil.GetEffectiveMaxLevelForPlayer does (a capped
    -- player level, such as a Classic pre-patch, wins).
    frame.levelText:SetText(ArenaPreviewLevelLabel())
    SetShown(frame.levelText, true)
  end

  local text = MSUF and MSUF.UFText
  local rt = frame._msufTextRuntime
  if not (text and text.UpdateTextSlots and rt) then
    return
  end
  rt.healthMissing = nil
  text.UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.MSUFUnitKey, ArenaPreviewPercent, rt.healthNeedsPercent, rt)
  text.UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.MSUFUnitKey, ArenaPreviewPowerPercent, rt.powerNeedsPercent, rt)
end

local function ApplyArenaPreviewFrameData(frame, index)
  if not frame then
    return
  end
  index = tonumber(index) or 1
  local classToken = ARENA_PREVIEW_CLASSES[index] or "MAGE"
  local pct = ARENA_PREVIEW_HP_PERCENT[index] or 65
  local hpMax = 1000000
  local hp = math.floor(hpMax * pct / 100)
  local powerMax = 240000
  local power = powerMax

  frame._msufArenaPreviewForced = true
  local state = frame._msufUnitState
  if SeedPreviewIdentity(state) then
    state.connectedKnown = true
    state.identityIsPlayerRead = true
    state.isPlayer = true
    state.isPlayerKnown = true
    state.identityClassRead = true
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    state.className = (type(names) == "table" and names[classToken]) or classToken
    state.classToken = classToken
  end

  local r, g, b, a = ResolveArenaPreviewHealthColor(frame, pct / 100, classToken)
  SetBarPreview(frame.hpBar or frame.Health, hp, hpMax, r, g, b, a)
  frame._msufAlphaLastHP = nil
  SetBarPreview(frame.targetPowerBar or frame.powerBar or frame.Power, power, powerMax, 0.05, 0.64, 0.92)
  ApplyArenaPreviewText(frame, hp, hpMax, power, powerMax, classToken)
end

-- Capture a family's stable data once. Resolved apply/cleanup state is private
-- lifecycle bookkeeping, never an additional activation request.
local function BuildFrameOperations(kind, forcedKey, paint, clear, trinkets)
  local units = { kind .. "1", kind .. "2", kind .. "3", kind .. "4", kind .. "5" }
  -- The client publishes its fixed supported slot count before elements load.
  local count = kind == "boss" and 5 or (tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3)
  local function ApplyFrames(active)
    local cleared = false
    local frames = UF.frames
    for i = 1, count do
      local unit = units[i]
      local frame = frames and frames[unit]
      if frame and active and UnitExistsPlain(unit) ~= true then
        frame:Show()
        if frame.SetAlpha then frame:SetAlpha(1) end
        if frame.EnableMouse then frame:EnableMouse(true) end
        paint(frame, i)
      elseif frame then
        if clear(frame, true) then cleared = true end
      end
    end
    if cleared then RequestBossRangeRefresh() end
    if trinkets then MSUF.Require("MSUF_ArenaTrinkets_SyncPreview", FILE)() end
  end
  local function ReapplyAlpha(reason)
    local frames = UF.frames
    for i = 1, count do RefreshHealthAlpha(frames and frames[units[i]]) end
    return UF.RefreshElements(kind, ALPHA_ELEMENTS, reason)
  end
  local function FramesReady(active)
    local frames = UF.frames
    if type(frames) ~= "table" then return false end
    local sawFrame = false
    for i = 1, count do
      local frame = frames[units[i]]
      if frame then
        sawFrame = true
        if active then
          if frame[forcedKey] ~= true then return false end
          if frame.IsShown and not frame:IsShown() then return false end
        elseif frame[forcedKey] == true then return false end
      end
    end
    return sawFrame
  end
  -- An unsupported family has no frame work. Keep its forward trinket
  -- collaborator and alpha refresh, without entering empty frame loops.
  if count == 0 then
    ApplyFrames = function() MSUF.Require("MSUF_ArenaTrinkets_SyncPreview", FILE)() end
    ReapplyAlpha = function(reason) return UF.RefreshElements(kind, ALPHA_ELEMENTS, reason) end
    FramesReady = function() return false end
  end
  return ApplyFrames, ReapplyAlpha, FramesReady, units, count
end

local function BuildLifecycle(kind, prefix, castbar, paint, clear, forcedKey)
  local trinkets = kind == "arena"
  local applyFrames, reapplyAlpha, framesReady, units, count = BuildFrameOperations(kind, forcedKey, paint, clear, trinkets)
  local appliedActive, cleanupPending
  local baseReason = "MSUF_" .. prefix .. "_PREVIEW"
  local syncReason, offReason = baseReason .. "_SYNC", baseReason .. "_OFF"
  local lightReasons = { [baseReason] = true, [syncReason] = true, [offReason] = true,
    ["MSUF2_" .. prefix .. "_PAGE_CORE"] = true, ["MSUF2_" .. prefix .. "_PAGE_FALLBACK"] = true }
  local pageKey = kind .. "Page"
  local clearPage, enablePage = Preview.Bind(pageKey, nil), Preview.Bind(pageKey, true)
  local function ClearCombat()
    if state[pageKey] ~= nil then clearPage() end
    local cleared = false
    local frames = UF.frames
    for i = 1, count do
      if clear(frames and frames[units[i]], true) then cleared = true end
    end
    if cleared then
      cleanupPending = true
      RequestBossRangeRefresh()
      if trinkets then MSUF.Require("MSUF_ArenaTrinkets_SyncPreview", FILE)() end
    end
    return cleared
  end
  if count == 0 then
    ClearCombat = function()
      if state[pageKey] ~= nil then clearPage() end
      return false
    end
  end
  local function ApplyUnlocked(active, reason)
    local UF = UF
    local refreshReason = reason or baseReason
    if cleanupPending ~= true and appliedActive == active and not (UF.Config and UF.Config.dirty == true)
      and lightReasons[refreshReason] == true and framesReady(active) then
      applyFrames(active)
      if active then reapplyAlpha(refreshReason) end
      return true
    end
    -- Seed missing opponents before structural refresh, then repaint after it.
    applyFrames(active)
    UF.RefreshVisibilityDrivers(kind)
    UF.RefreshElements(kind, REFRESH_ELEMENTS, refreshReason)
    UF.UpdateRuntime(kind, refreshReason)
    if active then applyFrames(true) end
    reapplyAlpha(refreshReason)
    MSUF.MSUF_Auras3.RequestScope(kind, baseReason)
    MSUF.Require(castbar, FILE)()
    local em2 = _G.MSUF_EM2
    if em2 and em2.Movers and type(em2.Movers.SyncAll) == "function" then em2.Movers.SyncAll() end
    appliedActive = active
    cleanupPending = nil
    return true
  end
  local function Apply(active, reason)
    active = active == true
    if BossPreviewCombatLocked() then
      ClearCombat()
      return false
    end
    return ApplyUnlocked(active, reason)
  end
  local function ApplyPage(active, reason)
    if BossPreviewCombatLocked() then
      ClearCombat()
      return false
    end
    active = active == true
    if active then enablePage() else clearPage() end
    return ApplyUnlocked(active, reason or baseReason)
  end
  local function Sync()
    if BossPreviewCombatLocked() then
      ClearCombat()
      return false
    end
    local active = state[pageKey] == true
      or (state.editMode == true and (state[kind] == true or state.all == true))
    return ApplyUnlocked(active, active and syncReason or offReason)
  end
  return Apply, ClearCombat, ApplyPage, Sync
end

local applyBoss, clearBoss, pageBoss, syncBoss = BuildLifecycle("boss", "BOSS",
  "MSUF_UpdateBossCastbarPreview", ApplyBossPreviewFrameData, ClearBossPreviewFrameForRuntime, "_msufBossPreviewForced")
UF.ApplyBossPreviewState, UF.ClearBossPreviewFramesForCombat = applyBoss, clearBoss
ExportPublic("MSUF_ClearBossUnitframePreviewForCombat", clearBoss)
ExportPublic("MSUF_ApplyBossUnitframePreviewState", pageBoss)
ExportPublic("MSUF_SyncBossUnitframePreviewWithUnitEdit", syncBoss)

local applyArena, clearArena, pageArena, syncArena = BuildLifecycle("arena", "ARENA",
  "MSUF_UpdateArenaCastbarPreview", ApplyArenaPreviewFrameData, ClearArenaPreviewFrameForRuntime, "_msufArenaPreviewForced")
UF.ApplyArenaPreviewState, UF.ClearArenaPreviewFramesForCombat = applyArena, clearArena
ExportPublic("MSUF_ClearArenaUnitframePreviewForCombat", clearArena)
ExportPublic("MSUF_ApplyArenaUnitframePreviewState", pageArena)
ExportPublic("MSUF_SyncArenaUnitframePreviewWithUnitEdit", syncArena)
