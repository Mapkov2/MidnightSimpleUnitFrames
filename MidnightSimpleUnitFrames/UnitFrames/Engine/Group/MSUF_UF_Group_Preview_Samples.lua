--- Fake roster identity, bars, texts and status painting. Each paint receives its owning scene.
local addonName, MSUF = ...
local GF = MSUF.GF
local Style = assert(GF.PreviewStyle, "Group preview requires PreviewStyle")
local InCombat = Style.InCombat
local PreviewAnimationActive = Style.PreviewAnimationActive
local PreviewLayerOn = Style.PreviewLayerOn
local SetShown = Style.SetShown
local SetText = Style.SetText
local Layout = assert(GF.PreviewLayout, "Group preview requires PreviewLayout")
local NormalizeKind = Layout.NormalizeKind
local GetPreviewAnimationFrameState = MSUF.Require("MSUF_GetPreviewAnimationFrameState", "GroupFrames/Preview")
local UnitName = UnitName
local issecretvalue = issecretvalue
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local floor = math.floor
local max = math.max
local min = math.min
local type = type
local tonumber = tonumber
local tostring = tostring

-- Resolve forward/cold exports at use time, preserving the existing dependency boundary.
local function Dep(name)
  return MSUF.Require(name, "UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
end

local PREVIEW_CLASSES = {
  "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
  "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID",
  "DEMONHUNTER", "EVOKER",
}
--- Index 1 always draws the real player name, so entry 1 only surfaces on a
--- wrap deep inside a raid preview. The lore names keep the party preview as
--- it was; the crew below fills the extra raid rows.
local PREVIEW_NAMES = {
  "Mapko", "Jaina", "Thrall", "Tyrande", "Anduin",
  "Aur0r4", "Dun", "Sif", "Jayee", "Kev", "Slickrock", "Uplift", "Zaazu", "Sha", "B3NZII",
}
local PREVIEW_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "HEALER" }

--- The sample member a grid slot of a scene shows. The slot is a position (layout, pool); the member decides role,
--- class, name and the painted data, all read from frame._msufGFPreviewIndex. The two are the same today: a
--- sorted preview order changes only this function.
local function PreviewMember(scene, slot)
  return slot
end
function GF.PreviewSampleRole(frame)
  local scene = frame and (frame._msufGFPreviewScene or frame._msufPreviewScene)
  return scene and scene.role or PREVIEW_ROLES[(((frame and frame._msufGFPreviewIndex) or 1) - 1) % #PREVIEW_ROLES + 1]
end

--- A raid subgroup is always five roster slots, and the preserved-group layout
--- blocks the preview by exactly that (SetPreservedPreviewPoint derives its
--- block from floor((index - 1) / 5)). Deriving the label from the same term is
--- what keeps the printed number on the block the geometry actually drew; the
--- roster position inside the group is not the group. Clamp at the eight groups
--- a raid can hold so an oversized preview count cannot print a fake "(9)".
local function PreviewSubgroup(index)
  local subgroup = floor((index - 1) / 5) + 1
  return subgroup > 8 and 8 or subgroup
end

--- Format a fake subgroup label exactly like the live raid-group indicator, so
--- the preview does not drift from the runtime formatter.
local function RaidGroupPreviewText(style, subgroup)
  local runtime = MSUF.UFStatusRuntime
  local format = runtime and runtime.RaidGroupText
  if type(format) == "function" then return format(style, subgroup) end
  if style == "BRACKET" then return "[" .. subgroup .. "]" end
  if style == "NONE" then return tostring(subgroup) end
  return "(" .. subgroup .. ")"
end

local function SetBar(bar, value, maxValue, animate, r, g, b, a, isolated)
  if not bar then return end
  if bar.SetMinMaxValues then bar:SetMinMaxValues(0, maxValue or 100) end
  if isolated then
    a = bar._msufA or a
    if not animate then bar._msufDirectValuePlain = nil end
    MSUF.UFBarTextCommon.SetBarValuePlain(bar, value or 0, animate == true)
  elseif bar.SetValue then bar:SetValue(value or 0, animate == true and bar._msufSmoothInterp or nil) end
  if bar.SetStatusBarColor then bar:SetStatusBarColor(r or 1, g or 1, b or 1, a or 1) end
  if bar.Show then bar:Show() end
end

local function ClassColor(class)
  local r, g, b = Dep("MSUF_UFCore_GetClassBarColorFast")(class)
  if r then return r, g, b end
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 0.25, 0.75, 0.30
end

local function PreviewNameColor(kind, class)
  if GF.ResolveNameColor then
    return GF.ResolveNameColor(kind, class)
  end
  return ClassColor(class)
end

local function PreviewHealthColor(frame, class, hpPct)
  local health = frame and frame.MSUFSpec and frame.MSUFSpec.health
  local mode = health and health.mode
  if mode == "gradient" then
    local common = MSUF and MSUF.UFBarTextCommon
    if common and type(common.PreviewHealthGradientColor) == "function" then
      local r, g, b = common.PreviewHealthGradientColor(health, hpPct)
      if r ~= nil then return r, g, b end
    end
    local p = max(0, min(1, tonumber(hpPct) or 0.72))
    local lr, lg, lb = health.gradientLowR or 1, health.gradientLowG or 0, health.gradientLowB or 0
    local mr, mg, mb = health.gradientMidR or 1, health.gradientMidG or 1, health.gradientMidB or 0
    local hr, hg, hb = health.gradientHighR or 0, health.gradientHighG or 1, health.gradientHighB or 0
    if p <= 0.5 then
      local t = p * 2
      return lr + (mr - lr) * t, lg + (mg - lg) * t, lb + (mb - lb) * t
    end
    local t = (p - 0.5) * 2
    return mr + (hr - mr) * t, mg + (hg - mg) * t, mb + (hb - mb) * t
  elseif mode == "custom" or mode == "unified" or mode == "dark" then
    return health.r or 0.1, health.g or 0.6, health.b or 0.9
  end
  return ClassColor(class)
end

-- Samples use whole percentages. These immutable readers retain the value
-- in their own closure, so nested paints share no mutable callback state and
-- ordinary repaints allocate no health/power reader. Unusual samples outside
-- that range retain the original value and behavior.
local function FixedPercent(pct)
  return function() return pct end
end
local percentReaders = {}
for pct = 0, 100 do percentReaders[pct] = FixedPercent(pct) end
local function PercentFactory(pct)
  pct = floor((pct or 0) + 0.5)
  return percentReaders[pct] or FixedPercent(pct)
end

--- Name, health and power text are one layer chip. Blanking the strings rather
--- than hiding them keeps the runtime's own show/hide state untouched, so the
--- chip going back on restores exactly the slots the settings ask for.
local PREVIEW_TEXT_REGIONS = {
  "nameText", "hpTextLeft", "hpTextCenter", "hpTextRight",
  "powerTextLeft", "powerTextCenter", "powerTextRight",
}

local function ClearPreviewTexts(frame)
  for i = 1, #PREVIEW_TEXT_REGIONS do SetText(frame[PREVIEW_TEXT_REGIONS[i]], "") end
end

local function ApplyPreviewText(frame, hp, hpMax, power, powerMax, class, absorb, isolated)
  local text = MSUF and MSUF.UFText
  local rt = frame and frame._msufTextRuntime
  if not (text and rt and text.UpdateTextSlots) then return end

  rt.healthMissing = max(0, (hpMax or 0) - (hp or 0))
  -- A scene sample carries the absorb amount its absorb text and combined health text show (the live frame asks
  -- the unit for it); nil clears the previous one.
  if isolated then
    rt.healthAbsorb = absorb
  end
  text.UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.MSUFUnitKey or "player",
    PercentFactory((hp / max(hpMax, 1)) * 100), rt.healthNeedsPercent, rt)
  if isolated and absorb ~= nil and (rt.healthAbsorbSlotCount or 0) > 0 then
    text.UpdateTextSlots(rt.healthAbsorbSlots, rt.healthAbsorbSlotCount, nil, nil, frame.MSUFUnitKey or "player", nil, false, rt)
  end
  if rt.healthColorByClass == true and text.SetHealthTextColor then
    local r, g, b = ClassColor(class)
    text.SetHealthTextColor(frame, rt, r, g, b, rt.healthTextAlpha or rt.textColorA or 1)
  elseif rt.healthColorByHealth == true and text.UpdateHealthTextColor then
    if isolated and text.SetSampleHealthTextColor then
      text.SetSampleHealthTextColor(frame, rt, hp, hpMax)
    else
      text.UpdateHealthTextColor(frame, rt, frame.MSUFUnitKey, hp, hpMax)
    end
  end

  text.UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.MSUFUnitKey or "player", PercentFactory((power / max(powerMax, 1)) * 100),
      rt.powerNeedsPercent, rt)
end

local function ApplyRoleIcon(frame, kind, role)
  if not frame.roleIcon then return end
  local status = frame.MSUFSpec and frame.MSUFSpec.status
  if not (GF.GetRoleTexture and status and status.role) then
    frame.roleIcon:Hide()
    return
  end
  local path, l, r, t, b = GF.GetRoleTexture(kind, role, status.role.style)
  if path then
    frame.roleIcon:SetTexture(path)
    frame.roleIcon:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
    frame.roleIcon:Show()
  else
    frame.roleIcon:Hide()
  end
end

local function ApplyLeaderIcon(frame, kind, assist)
  local tex = assist and frame.assistIcon or frame.leaderIcon
  if not tex then return end
  local fn = assist and GF.GetAssistTexture or GF.GetLeaderTexture
  if type(fn) ~= "function" then
    tex:Hide()
    return
  end
  local path, l, r, t, b = fn(kind)
  tex:SetTexture(path)
  tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
  tex:Show()
end

--- Every region this seeds belongs to the Status layer, so one gate at the top
--- is the whole chip: hiding them all is exactly what ClearPreviewData does,
--- except that ClearPreviewData keeps the combat-state icon (keepCombatIcon),
--- the one status chip only the layer gate hides. Kept inline: preview
--- repaints run per animation tick.
local function HidePreviewStatus(frame, keepCombatIcon)
  SetShown(frame.roleIcon, false)
  SetShown(frame.leaderIcon, false)
  SetShown(frame.assistIcon, false)
  SetShown(frame.raidIcon, false)
  SetShown(frame.readyCheckIcon, false)
  SetShown(frame.resurrectIcon or frame.incomingResIndicatorIcon, false)
  SetShown(frame.pvpIcon or frame.pvpIndicatorIcon, false)
  SetShown(frame.phaseIcon, false)
  SetShown(frame.raidGroupNameText, false)
  SetShown(frame.levelText, false)
  if not keepCombatIcon then SetShown(frame.combatStateIndicatorIcon, false) end
  SetShown(frame.statusIndicatorText, false)
  SetShown(frame.statusAFKTimerText, false)
end

local function ApplyPreviewStatus(frame, kind, index, role, scene, sample)
  local regions = sample and sample.statusRegions
  if regions then
    local status, runtime = frame.MSUFSpec.status, MSUF.UFStatusRuntime
    MSUF.UF.elements.StatusIndicators.SceneApply(frame, frame.MSUFSpec)
    runtime.PaintSampleIdentityTexts(frame, status, sample)
    runtime.PaintSampleIndicators(frame, status, sample)
    runtime.PaintSceneStatus(frame, status, sample.statusSelection, sample)
    for i = 1, #regions do
      local row = regions[i]
      local region = frame[row.field]
      if region then
        if row.text ~= nil then region:SetText(row.text)
        elseif row.texture then
          region:SetTexture(row.texture)
          region:SetTexCoord(row.l or 0, row.r or 1, row.t or 0, row.b or 1)
        end
        region:SetShown(row.shown == true and PreviewLayerOn("status", scene))
        region:SetAlpha((region._msufStatusAlpha or 1) * (frame._msufAlphaLastFG or 1))
      end
    end
    return
  end
  if not PreviewLayerOn("status", scene) then
    HidePreviewStatus(frame)
    return
  end
  ApplyRoleIcon(frame, kind, role)
  if index == 1 then ApplyLeaderIcon(frame, kind, false) else SetShown(frame.leaderIcon, false) end
  if index == 2 then ApplyLeaderIcon(frame, kind, true) else SetShown(frame.assistIcon, false) end
  if frame.raidIcon and index == 1 then
    frame.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    frame.raidIcon:SetTexCoord(0, 0.25, 0, 0.25)
    frame.raidIcon:Show()
  else
    SetShown(frame.raidIcon, false)
  end
  if frame.readyCheckIcon and (index == 1 or index == 3) then
    frame.readyCheckIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    frame.readyCheckIcon:Show()
  else
    SetShown(frame.readyCheckIcon, false)
  end
  if frame.resurrectIcon and index == 3 then
    frame.resurrectIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
    frame.resurrectIcon:Show()
  else
    SetShown(frame.resurrectIcon or frame.incomingResIndicatorIcon, false)
  end
  local pvpIcon = frame.pvpIcon or frame.pvpIndicatorIcon
  if pvpIcon and index == 2 then
    if pvpIcon.SetAtlas then
      pvpIcon:SetAtlas("UI-HUD-UnitFrame-Player-PVP-AllianceIcon")
    else
      pvpIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Alliance")
      if pvpIcon.SetTexCoord then pvpIcon:SetTexCoord(0, 1, 0, 1) end
    end
    pvpIcon:Show()
  else
    SetShown(pvpIcon, false)
  end
  if frame.phaseIcon and index == 4 then
    frame.phaseIcon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
    frame.phaseIcon:Show()
  else
    SetShown(frame.phaseIcon, false)
  end
  --- The compiled status always carries a raidGroup table, so gate on its
  --- enabled flag: testing the table alone kept a stale number on screen after
  --- the setting was switched off.
  local raidGroupCfg = frame.MSUFSpec and frame.MSUFSpec.status and frame.MSUFSpec.status.raidGroup
  if frame.raidGroupNameText and raidGroupCfg and raidGroupCfg.enabled == true then
    frame.raidGroupNameText:SetText(RaidGroupPreviewText(raidGroupCfg.style, PreviewSubgroup(index)))
    frame.raidGroupNameText:Show()
  else
    SetShown(frame.raidGroupNameText, false)
  end
  --- Preview members are friendly, so a graded level text sits in the standard
  --- band - the same color a real party member gets.
  local levelCfg = frame.MSUFSpec and frame.MSUFSpec.status and frame.MSUFSpec.status.level
  if frame.levelText and levelCfg and levelCfg.enabled == true then
    local playerLevel = (not scene or scene.default) and UnitLevel and tonumber(UnitLevel("player")) or nil
    frame.levelText:SetText(tostring(playerLevel and playerLevel > 0 and playerLevel or 80))
    local statusRuntime = MSUF.UFStatusRuntime
    if levelCfg.difficultyColor == true and statusRuntime and statusRuntime.ApplyLevelDifficultyColor then
      statusRuntime.ApplyLevelDifficultyColor(frame.levelText, frame, nil, nil, levelCfg, 3)
    end
    frame.levelText:Show()
    if statusRuntime and statusRuntime.SetForeverLevelBadgeShown then
      statusRuntime.SetForeverLevelBadgeShown(frame, levelCfg.foreverBadge == true)
    end
  else
    SetShown(frame.levelText, false)
    local statusRuntime = MSUF.UFStatusRuntime
    if statusRuntime and statusRuntime.SetForeverLevelBadgeShown then
      statusRuntime.SetForeverLevelBadgeShown(frame, false)
    end
  end
  SetShown(frame.combatStateIndicatorIcon, false)
  SetShown(frame.statusIndicatorText, false)
  SetShown(frame.statusAFKTimerText, false)
end

--- Sample heal prediction, absorb and heal-absorb bars of a scene frame (fractions of the health bar). The
--- prediction element paints them from the compiled prediction settings, like a live frame, without a unit.
local function ApplyScenePrediction(frame, sample, hpPct, animState)
  local prediction = MSUF.UF.ApplyPredictionPreview
  if not prediction then return end
  local heal, absorb = sample and sample.healPct, sample and sample.absorbPct
  if animState then
    heal = max(0.01, min(0.24, tonumber(animState.healPct) or heal or 0.12))
    absorb = max(0.01, min(0.24, tonumber(animState.absorbPct) or absorb or 0.08))
  end
  prediction(frame, hpPct * 100, heal and heal * 100, absorb and absorb * 100, sample and sample.healAbsorbPct and sample.healAbsorbPct * 100)
end

--- Seed fake unit state into one preview frame after UF.ApplySpec has built the
--- regions. Keep this data fake/local; live group frames own real roster state.
local function PaintSceneHealth(frame, hp, hpMax, animState, class, hpPct)
  local bar = frame.hpBar or frame.Health or frame.health
  bar:SetMinMaxValues(0, hpMax)
  if not animState then bar._msufDirectValuePlain = nil end
  MSUF.UFBarTextCommon.SetBarValuePlain(bar, hp, animState ~= nil and bar._msufDirectValuePlain == true)
  bar:SetStatusBarColor(PreviewHealthColor(frame, class, hpPct))
  bar:Show()
end

local function ApplyPreviewData(frame, slot, kind, scene)
  if InCombat() then return false end
  if not frame then return false end
  if not frame.MSUFSpec then return false end
  kind = NormalizeKind(kind) or "party"
  local isolatedScene = scene and not scene.default and scene
  local owner = isolatedScene and isolatedScene.root
  local elapsed = owner and owner.animating and owner.elapsed
  -- The member this frame shows was chosen when the frame was prepared for its slot (PreviewMember).
  local index = frame._msufGFPreviewIndex or slot
  -- A scene can pin one sample (name, class, fractions) for all its rows; see Scene:SetSample.
  local sample = isolatedScene and isolatedScene.sample
  local class = sample and sample.class or PREVIEW_CLASSES[((index - 1) % #PREVIEW_CLASSES) + 1]
  local role = PREVIEW_ROLES[((index - 1) % #PREVIEW_ROLES) + 1]
  -- An isolated scene never asks the client who the player is: every index draws its sample name.
  local playerName = not isolatedScene and UnitName and UnitName("player")
  -- Preview identities are synthetic; an unreadable player name uses the same
  -- sample as an unavailable name, before shortening or caching it.
  if issecretvalue(playerName) then playerName = nil end
  local name = sample and sample.name or (index == 1 and playerName) or PREVIEW_NAMES[((index - 1) % #PREVIEW_NAMES) + 1]
  -- The pinned class is also the class the frame's name colour and portrait art draw (a scene frame holds no unit).
  local classPinned = sample and sample.class and frame._msufPortraitSampleClass ~= class
  if classPinned then frame._msufPortraitSampleClass = class end

  frame._msufGFPreviewActive = true
  frame._msufGFPreviewIndex = index
  frame._msufGFPreviewClass = class
  frame._msufGFPreviewRole = role
  frame._msufGFIsPreviewFrame = true
  frame._msufIsGroupFrame = true
  frame._msufGFKind = kind

  local textLayerOn = PreviewLayerOn("text", scene)
  local showPreviewName = frame.nameText and frame.nameText:IsShown() and textLayerOn
  -- Keep the fake identity authoritative when ordinary unit events refresh the
  -- player-backed dummy outside Edit Mode.
  frame._msufPreviewNameText = (showPreviewName or isolatedScene) and (name or "Preview") or nil
  if showPreviewName then
    -- The engine paints the sample name: UTF-8 aware legacy shortening, or the
    -- full name inside the layout's clip window, exactly like a live frame.
    if isolatedScene then
      MSUF.UFText.PaintSampleName(frame, name or "Preview")
    else
      MSUF.UFText.UpdateName(frame, "MSUF_PREVIEW_NAME", frame.MSUFUnitKey)
    end
    local r, g, b = PreviewNameColor(kind, class)
    local a = GF.ResolveFontTextAlpha and GF.ResolveFontTextAlpha(kind) or 1
    frame.nameText:SetTextColor(r, g, b, a)
    frame.nameText:Show()
  end

  local hpPct = sample and sample.hpPct or min(0.95, 0.34 + (((index * 13) % 55) * 0.01))
  local animState
  if isolatedScene then
    -- The scene's own clock, not the shared preview animation: scenes animate only while their owner hands one over.
    if elapsed then
      animState = Dep("MSUF_BuildPreviewAnimationFrameState")(frame, index, kind, frame._msufGFPreviewAnimState or {},
        elapsed, frame.MSUFSpec.health.chunked == true, frame.MSUFSpec.power.chunked == true)
    end
  elseif PreviewAnimationActive() then
    animState = GetPreviewAnimationFrameState(frame, index, kind, frame._msufGFPreviewAnimState or {})
  end
  if animState then
    frame._msufGFPreviewAnimState = animState
    hpPct = min(0.98, max(0.02, tonumber(animState.hpPct) or hpPct))
  end
  local hpMax = sample and sample.hpMax or 100
  local hp = floor(hpPct * hpMax + 0.5)
  if isolatedScene then PaintSceneHealth(frame, hp, hpMax, animState, class, hpPct)
  else SetBar(frame.hpBar or frame.Health or frame.health, hp, hpMax, true, PreviewHealthColor(frame, class, hpPct)) end
  if isolatedScene then
    -- A scene frame holds no unit: the dynamic background (health gradient, match health) takes the sample's health.
    local health = MSUF.UF.elements and MSUF.UF.elements.Health
    if health and health.PaintSampleBackground then health.PaintSampleBackground(frame, hp / hpMax) end
  end

  local powerMax = sample and sample.powerMax or 100
  local power = sample and sample.powerPct and floor(sample.powerPct * powerMax + 0.5) or min(powerMax, 35 + ((index * 11) % 55))
  if animState then
    power = min(powerMax, max(0, floor((tonumber(animState.powerPct) or (power / powerMax)) * powerMax + 0.5)))
  end
  local powerBar = frame.targetPowerBar or frame.powerBar or frame.Power or frame.power
  -- The layer only hides the drawn bar; the health geometry keeps following the
  -- settings, so switching the chip never fakes a layout change on the dummies.
  if powerBar and (not powerBar.IsShown or powerBar:IsShown()) then
    if PreviewLayerOn("power", scene) then
      local color = sample and sample.powerColor
      if color then
        SetBar(powerBar, power, powerMax, not isolatedScene or animState ~= nil, color[1], color[2], color[3], 1, isolatedScene)
      else
        SetBar(powerBar, power, powerMax, not isolatedScene or animState ~= nil, 0.10, 0.45, 0.95, 1, isolatedScene)
      end
    elseif powerBar.Hide then
      powerBar:Hide()
    end
  end

  if textLayerOn then
    ApplyPreviewText(frame, hp, hpMax, power, powerMax, class, sample and sample.absorb, isolatedScene)
  else
    ClearPreviewTexts(frame)
  end
  -- A scene frame skips the spec apply's live updates, so the elements whose update paints a preview sample (and
  -- reads no unit for a preview frame) run here.
  if isolatedScene then
    if sample then
      ApplyScenePrediction(frame, sample, hpPct, animState)
      local tempMax = MSUF.UF.elements and MSUF.UF.elements.TempMaxHealth
      if tempMax and tempMax.ApplySample then tempMax.ApplySample(frame, sample.tempMaxPct) end
    end
    if isolatedScene.bodyOnly then
      -- The owner draws the portrait, icons, auras and indicators (its handles) over this body.
      SetShown(frame.MSUFPortraitHolder, false)
      frame:Show()
      return true
    end
    local portrait = MSUF.UF.elements and MSUF.UF.elements.Portrait
    local art = sample and sample.portrait
    if (classPinned or art or frame._msufSamplePortraitArt) and portrait and portrait.SceneApply then
      frame._msufSamplePortraitArt = art and art.texture
      local spec = frame.MSUFSpec
      if art then
        isolatedScene.portraitSpecMeta.__index, isolatedScene.portraitConfigMeta.__index = spec, spec.portrait
        spec = isolatedScene.portraitSampleSpec
        local p = spec.portrait
        p.render = art.texture and "2D" or nil
        p.texL, p.texR, p.texT, p.texB = art.l, art.r, art.t, art.b
        local classArt = frame.MSUFSpec.portrait and frame.MSUFSpec.portrait.render == "CLASS"
        p.panOffsetX, p.panOffsetY = classArt and 0 or nil, classArt and 0 or nil
      end
      portrait.SceneApply(frame, spec)
    end
    if art and frame.MSUFPortraitHolder then
      frame.MSUFPortraitHolder:SetShown(art.shown == true and PreviewLayerOn("portrait", scene))
    end
    local threat = MSUF.UF.elements and MSUF.UF.elements.ThreatIndicator
    if threat and threat.Update then threat.Update(frame, "MSUF_PREVIEW") end
  end
  ApplyPreviewStatus(frame, kind, index, role, scene, sample)
  if animState and not (sample and sample.statusRegions) and frame.combatStateIndicatorIcon and PreviewLayerOn("status", scene) then
    if frame.combatStateIndicatorIcon.SetAlpha then frame.combatStateIndicatorIcon:SetAlpha(0.55 + ((animState.pulse or 0) * 0.45)) end
    frame.combatStateIndicatorIcon:Show()
  end
  if GF.PreviewSpellIndicators then GF.PreviewSpellIndicators(frame, kind, nil, nil, scene, sample) end
  if GF.PreviewFrameAuras then GF.PreviewFrameAuras(frame, kind, index, nil, nil, scene, sample) end
  frame:Show()
  return true
end
local function ClearPreviewData(frame)
  if not frame then return end
  frame._msufGFPreviewActive = nil
  frame._msufGFPreviewIndex = nil
  frame._msufPreviewNameText = nil
  SetText(frame.nameText, "")
  SetText(frame.hpTextLeft, "")
  SetText(frame.hpTextCenter, "")
  SetText(frame.hpTextRight, "")
  SetText(frame.powerTextLeft, "")
  SetText(frame.powerTextCenter, "")
  SetText(frame.powerTextRight, "")
  HidePreviewStatus(frame, true)
  if GF.HideSpellIndicators then GF.HideSpellIndicators(frame) end
  if GF.HideFrameAuras then GF.HideFrameAuras(frame) end
end

GF.PreviewSamples = {
  PREVIEW_CLASSES = PREVIEW_CLASSES,
  PREVIEW_NAMES = PREVIEW_NAMES,
  PreviewMember = PreviewMember,
  ApplyPreviewData = ApplyPreviewData,
  ClearPreviewData = ClearPreviewData,
}
