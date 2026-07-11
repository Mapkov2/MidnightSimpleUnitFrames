--- UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua
--- Non-combat preview frames for group-frame menu/edit workflows.
---
--- Preview frames reuse the same compiled specs and visual elements as live
--- group frames, but they use fake roster data and never join secure headers.
--- Runtime hides live headers while previews are active so both do not overlap.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local GF = MSUF.GF or {}
MSUF.GF = GF

local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetNumGroupMembers = GetNumGroupMembers
local UnitName = UnitName
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local C_Timer = _G.C_Timer
local floor, max, min = math.floor, math.max, math.min
local type, tonumber, tostring = type, tonumber, tostring
local NormalizeKind

GF._previewFrames = GF._previewFrames or {}
GF._previewActive = GF._previewActive or {}
GF._previewShownCounts = GF._previewShownCounts or {}
GF._previewAnchorFrame = GF._previewAnchorFrame or {}
GF._previewContainer = GF._previewContainer or {}
GF._previewLayoutFrame = GF._previewLayoutFrame or {}
GF._previewBuildSerial = GF._previewBuildSerial or {}

local PREVIEW_BUILD_SLICE_COUNT = 2
local PREVIEW_BUILD_SLICE_THRESHOLD = 8

local function BumpPreviewBuildSerial(kind)
  kind = NormalizeKind(kind) or kind
  if not kind then return 0 end
  GF._previewBuildSerial[kind] = (GF._previewBuildSerial[kind] or 0) + 1
  return GF._previewBuildSerial[kind]
end

local function CurrentPreviewBuildSerial(kind)
  return GF._previewBuildSerial[kind] or 0
end

local PREVIEW_CLASSES = {
  "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
  "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID",
  "DEMONHUNTER", "EVOKER",
}
local PREVIEW_NAMES = { "Mapko", "Jaina", "Thrall", "Tyrande", "Anduin" }
local PREVIEW_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "HEALER" }

local VALID_POINTS = {
  CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
  TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function PreviewAnimationActive()
  return type(_G.MSUF_IsPreviewAnimationEnabled) == "function" and _G.MSUF_IsPreviewAnimationEnabled() == true
end

function NormalizeKind(kind)
  if kind == "gf_party" then return "party" end
  if kind == "gf_raid" then return "raid" end
  if kind == "gf_mythicraid" then return "mythicraid" end
  if kind == "party" or kind == "raid" or kind == "mythicraid" then return kind end
  return nil
end

local function IsRaidLikeKind(kind)
  return kind == "raid" or kind == "mythicraid"
end

local function AnchorPoint(conf)
  local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
  if not VALID_POINTS[point] then point = "CENTER" end
  return point
end

local function PointFraction(point)
  local fx, fy
  if point == "LEFT" or point == "TOPLEFT" or point == "BOTTOMLEFT" then
    fx = 0
  elseif point == "RIGHT" or point == "TOPRIGHT" or point == "BOTTOMRIGHT" then
    fx = 1
  else
    fx = 0.5
  end
  if point == "BOTTOM" or point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" then
    fy = 0
  elseif point == "TOP" or point == "TOPLEFT" or point == "TOPRIGHT" then
    fy = 1
  else
    fy = 0.5
  end
  return fx, fy
end

local function ClampBoxAxis(minEdge, maxEdge, screenMax)
  local size = (maxEdge or 0) - (minEdge or 0)
  if size <= 0 or not (screenMax and screenMax > 0) then
    return 0
  end
  if size <= screenMax then
    if minEdge < 0 then return -minEdge end
    if maxEdge > screenMax then return screenMax - maxEdge end
    return 0
  end
  if minEdge > 0 then return -minEdge end
  if maxEdge < screenMax then return screenMax - maxEdge end
  return 0
end

local function ClampPreviewOffsetOnScreen(point, relative, x, y, totalW, totalH)
  if not (relative and relative.GetLeft and UIParent and UIParent.GetWidth) then
    return x, y
  end
  local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
  if not (screenW and screenH and screenW > 0 and screenH > 0) then
    return x, y
  end
  local pLeft, pRight = relative:GetLeft(), relative:GetRight()
  local pBottom, pTop = relative:GetBottom(), relative:GetTop()
  if not (pLeft and pRight and pBottom and pTop) then
    return x, y
  end
  local fx, fy = PointFraction(point)
  local px = pLeft + (pRight - pLeft) * fx + (x or 0)
  local py = pBottom + (pTop - pBottom) * fy + (y or 0)
  local boxW, boxH = totalW or 0, totalH or 0
  local left = px - boxW * fx
  local bottom = py - boxH * fy
  local dx = ClampBoxAxis(left, left + boxW, screenW)
  local dy = ClampBoxAxis(bottom, bottom + boxH, screenH)
  if dx == 0 and dy == 0 then return x, y end
  return (x or 0) + dx, (y or 0) + dy
end

local function ResolveAnchorFrame(conf)
  local name = conf and (conf.anchorToFrame or conf.anchorFrame or conf.relativeTo or conf.anchorTo)
  if type(name) == "string" and name ~= "" and name ~= "FREE" and name ~= "UIParent" then
    local UF = MSUF and MSUF.UF
    if UF and UF.frames and UF.frames[name] then return UF.frames[name] end
    if _G[name] then return _G[name] end
  end
  return UIParent
end

local function DefaultCenter(kind)
  if IsRaidLikeKind(kind) then return -500, 0 end
  return -400, 0
end

local function DefaultPreviewCount(kind)
  if kind == "mythicraid" then return 20 end
  if kind == "raid" then return 30 end
  return 5
end

local function ActivePreviewCount(kind)
  if not (GF._previewActive and GF._previewActive[kind] == true) then return nil end
  local n = tonumber(GF._previewShownCounts and GF._previewShownCounts[kind])
  if n and n > 0 then return floor(n + 0.5) end
  return DefaultPreviewCount(kind)
end

local function VisiblePreviewCount(kind, count)
  count = floor((tonumber(count) or 0) + 0.5)
  if count < 1 then return count end
  if GF.GetVisibleLayoutCount then
    return GF.GetVisibleLayoutCount(kind, count)
  end
  return count
end

local function GetPositionCount(kind)
  kind = NormalizeKind(kind) or "party"
  local previewCount = ActivePreviewCount(kind)
  if previewCount then return previewCount end

  local conf = GF.GetConf and GF.GetConf(kind) or {}
  if kind == "party" then
    local n = GetNumSubgroupMembers and (GetNumSubgroupMembers() or 0) or 0
    if n > 0 and conf.showPlayer ~= false then
      n = n + 1
    elseif n == 0 and conf.showSolo == true and conf.showPlayer ~= false then
      n = 1
    end
    if n > 0 then return n end
    return 5
  end
  if GF.GetLiveLayoutCount then
    local n = tonumber(GF.GetLiveLayoutCount(kind))
    if n and n > 0 then return floor(n + 0.5) end
  end
  local n = GetNumGroupMembers and (GetNumGroupMembers() or 0) or 0
  if n > 0 then return n end
  return kind == "mythicraid" and 20 or 40
end

function GF.SetPreviewAnchor(kind, parent)
  kind = NormalizeKind(kind)
  if not kind then return false end
  if GF._previewAnchorFrame[kind] == parent then return true end
  GF._previewAnchorFrame[kind] = parent
  BumpPreviewBuildSerial(kind)
  local container = GF._previewContainer and GF._previewContainer[kind]
  local layout = GF._previewLayoutFrame and GF._previewLayoutFrame[kind]
  if container then container._msufGFPreviewPositionKey = nil end
  if layout then layout._msufGFPreviewPositionKey = nil end
  return true
end

local PreviewsAllowed

local function EnsureContainer(kind, parent)
  local desiredParent = parent or UIParent
  local container = GF._previewContainer[kind]
  if not container then
    container = CreateFrame("Frame", "MSUF_GFPreviewContainer_" .. kind, desiredParent)
    container:EnableMouse(false)
    GF._previewContainer[kind] = container
  end
  if container:GetParent() ~= desiredParent then container:SetParent(desiredParent) end

  local layout = GF._previewLayoutFrame[kind]
  if not layout then
    layout = CreateFrame("Frame", "MSUF_GFPreviewLayout_" .. kind, container)
    layout:EnableMouse(false)
    GF._previewLayoutFrame[kind] = layout
  end
  if layout:GetParent() ~= container then layout:SetParent(container) end
  return container, layout
end

--- Position the preview container using the same grid math as live headers so
--- menu edits match the real layout as closely as possible.
local function PositionContainer(kind, count)
  local conf = GF.GetConf and GF.GetConf(kind) or {}
  local posCount = GetPositionCount(kind) or DefaultPreviewCount(kind)
  local dx, dy, posW, posH = GF.GetGridMetrics(kind, posCount)
  local _, _, _, _, w, h, spacing, growth, upc, _, _, _, primary, _, _, blockW, blockH = GF.GetGridMetrics(kind, count)
  local parent = GF._previewAnchorFrame and GF._previewAnchorFrame[kind]
  local container, layout = EnsureContainer(kind, parent or UIParent)

  local containerW, containerH = max(posW or w or 1, 1), max(posH or h or 1, 1)
  local point, relative, x, y
  if parent then
    point, relative, x, y = "CENTER", parent, 0, 0
  else
    local cx, cy = tonumber(conf.offsetX), tonumber(conf.offsetY)
    if cx == nil or cy == nil then cx, cy = DefaultCenter(kind) end
    point, relative, x, y = AnchorPoint(conf), ResolveAnchorFrame(conf), floor(cx + 0.5), floor(cy + 0.5)
    x, y = ClampPreviewOffsetOnScreen(point, relative, x, y, containerW, containerH)
  end
  local containerKey = tostring(point) .. "\030" .. tostring(relative) .. "\030" .. tostring(x) .. "\030" .. tostring(y)
    .. "\030" .. tostring(containerW) .. "\030" .. tostring(containerH)
  if container._msufGFPreviewPositionKey ~= containerKey then
    container._msufGFPreviewPositionKey = containerKey
    container:ClearAllPoints()
    container:SetSize(containerW, containerH)
    container:SetPoint(point, relative, point, x, y)
  end

  local layoutW, layoutH = containerW, containerH
  local layoutPoint = AnchorPoint(conf)
  local layoutKey = tostring(layoutPoint) .. "\030" .. tostring(dx or 0) .. "\030" .. tostring(dy or 0)
    .. "\030" .. tostring(layoutW) .. "\030" .. tostring(layoutH) .. "\030" .. tostring(container)
  if layout._msufGFPreviewPositionKey ~= layoutKey then
    layout._msufGFPreviewPositionKey = layoutKey
    layout:ClearAllPoints()
    layout:SetSize(layoutW, layoutH)
    layout:SetPoint(layoutPoint, container, layoutPoint, -(dx or 0), -(dy or 0))
  end
  layout.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ("gf_" .. kind)
  layout._msufIsGroupFrame = true
  layout._msufGFKind = kind
  layout._msufGFPreviewLayout = true
  layout._msufGFDragCenterToGridX = dx or 0
  layout._msufGFDragCenterToGridY = dy or 0
  container:Show()
  layout:Show()
  return container, layout, w, h, spacing or 1, growth or "DOWN", upc or 5, primary, blockW, blockH
end

local function SetShown(region, shown)
  if region and region.SetShown then region:SetShown(shown and true or false) end
end

local function SetText(region, text)
  if region and region.SetText then region:SetText(text or "") end
end

local function SetBar(bar, value, maxValue, r, g, b, a)
  if not bar then return end
  if bar.SetMinMaxValues then bar:SetMinMaxValues(0, maxValue or 100) end
  if bar.SetValue then bar:SetValue(value or 0) end
  if bar.SetStatusBarColor then bar:SetStatusBarColor(r or 1, g or 1, b or 1, a or 1) end
  if bar.Show then bar:Show() end
end

local function ClassColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 0.25, 0.75, 0.30
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

local function ShortName(name, frame)
  local rt = frame and frame._msufTextRuntime
  local maxChars = rt and tonumber(rt.nameShortenMax) or 0
  if maxChars > 0 and type(name) == "string" and #name > maxChars then
    return name:sub(1, maxChars) .. ((rt and rt.nameShortenDots == false) and "" or "...")
  end
  return name
end

local function PercentFactory(pct)
  pct = floor((pct or 0) + 0.5)
  return function() return pct end
end

local function ApplyPreviewText(frame, hp, hpMax, power, powerMax)
  local text = MSUF and MSUF.UFText
  local rt = frame and frame._msufTextRuntime
  if not (text and rt and text.UpdateTextSlots) then return end

  rt.healthMissing = max(0, (hpMax or 0) - (hp or 0))
  text.UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.unit, PercentFactory((hp / max(hpMax, 1)) * 100), rt.healthNeedsPercent, rt)

  text.UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.unit, PercentFactory((power / max(powerMax, 1)) * 100), rt.powerNeedsPercent, rt)
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
  if type(fn) ~= "function" then tex:Hide(); return end
  local path, l, r, t, b = fn(kind)
  tex:SetTexture(path)
  tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
  tex:Show()
end

local function ApplyPreviewStatus(frame, kind, index, role)
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
  if frame.raidGroupNameText and frame.MSUFSpec and frame.MSUFSpec.status and frame.MSUFSpec.status.raidGroup then
    frame.raidGroupNameText:SetText(tostring(((index - 1) % 5) + 1))
    frame.raidGroupNameText:Show()
  else
    SetShown(frame.raidGroupNameText, false)
  end
  SetShown(frame.combatStateIndicatorIcon, false)
  SetShown(frame.statusIndicatorText, false)
end

--- Seed fake unit state into one preview frame after UF.ApplySpec has built the
--- regions. Keep this data fake/local; live group frames own real roster state.
local function ApplyPreviewData(frame, index, kind)
  if not frame then return false end
  if not frame.MSUFSpec then return false end
  kind = NormalizeKind(kind) or "party"
  local class = PREVIEW_CLASSES[((index - 1) % #PREVIEW_CLASSES) + 1]
  local role = PREVIEW_ROLES[((index - 1) % #PREVIEW_ROLES) + 1]
  local playerName = UnitName and UnitName("player")
  local name = (index == 1 and playerName) or PREVIEW_NAMES[((index - 1) % #PREVIEW_NAMES) + 1]

  frame._msufGFPreviewActive = true
  frame._msufGFPreviewIndex = index
  frame._msufGFPreviewClass = class
  frame._msufGFPreviewRole = role
  frame._msufGFIsPreviewFrame = true
  frame._msufIsGroupFrame = true
  frame._msufGFKind = kind

  if frame.nameText and frame.nameText:IsShown() then
    frame.nameText:SetText(ShortName(name or "Preview", frame))
    frame.nameText:SetTextColor(ClassColor(class))
    frame.nameText:Show()
  end

  local hpPct = min(0.95, 0.34 + (((index * 13) % 55) * 0.01))
  local animState = PreviewAnimationActive() and _G.MSUF_GetPreviewAnimationFrameState
    and _G.MSUF_GetPreviewAnimationFrameState(frame, index, kind, frame._msufGFPreviewAnimState or {})
  if animState then
    frame._msufGFPreviewAnimState = animState
    hpPct = min(0.98, max(0.02, tonumber(animState.hpPct) or hpPct))
  end
  local hpMax = 100
  local hp = floor(hpPct * hpMax + 0.5)
  SetBar(frame.hpBar or frame.Health or frame.health, hp, hpMax, PreviewHealthColor(frame, class, hpPct))

  local powerMax = 100
  local power = min(powerMax, 35 + ((index * 11) % 55))
  if animState then
    power = min(powerMax, max(0, floor((tonumber(animState.powerPct) or (power / powerMax)) * powerMax + 0.5)))
  end
  local powerBar = frame.targetPowerBar or frame.powerBar or frame.Power or frame.power
  if powerBar and (not powerBar.IsShown or powerBar:IsShown()) then
    SetBar(powerBar, power, powerMax, 0.10, 0.45, 0.95, 1)
  end

  ApplyPreviewText(frame, hp, hpMax, power, powerMax)
  ApplyPreviewStatus(frame, kind, index, role)
  if animState and frame.combatStateIndicatorIcon then
    if frame.combatStateIndicatorIcon.SetAlpha then frame.combatStateIndicatorIcon:SetAlpha(0.55 + ((animState.pulse or 0) * 0.45)) end
    frame.combatStateIndicatorIcon:Show()
  end
  if GF.PreviewSpellIndicators then GF.PreviewSpellIndicators(frame, kind, nil, nil) end
  if GF.PreviewFrameAuras then GF.PreviewFrameAuras(frame, kind, index) end
  frame:Show()
  return true
end

local function ClearPreviewData(frame)
  if not frame then return end
  frame._msufGFPreviewActive = nil
  frame._msufGFPreviewIndex = nil
  SetText(frame.nameText, "")
  SetText(frame.hpTextLeft, "")
  SetText(frame.hpTextCenter, "")
  SetText(frame.hpTextRight, "")
  SetText(frame.powerTextLeft, "")
  SetText(frame.powerTextCenter, "")
  SetText(frame.powerTextRight, "")
  SetShown(frame.roleIcon, false)
  SetShown(frame.raidIcon, false)
  SetShown(frame.leaderIcon, false)
  SetShown(frame.assistIcon, false)
  SetShown(frame.readyCheckIcon, false)
  SetShown(frame.resurrectIcon or frame.incomingResIndicatorIcon, false)
  SetShown(frame.pvpIcon or frame.pvpIndicatorIcon, false)
  SetShown(frame.phaseIcon, false)
  SetShown(frame.raidGroupNameText, false)
  SetShown(frame.statusIndicatorText, false)
  if GF.HideSpellIndicators then GF.HideSpellIndicators(frame) end
  if GF.HideFrameAuras then GF.HideFrameAuras(frame) end
end

local function PlacePreviewFrame(frame, layout, index, w, h, spacing, growth, upc)
  local row = (index - 1) % upc
  local col = floor((index - 1) / upc)
  if growth == "UP" then
    frame:SetPoint("BOTTOMLEFT", layout, "BOTTOMLEFT", col * (w + spacing), row * (h + spacing))
  elseif growth == "RIGHT" then
    frame:SetPoint("TOPLEFT", layout, "TOPLEFT", row * (w + spacing), -col * (h + spacing))
  elseif growth == "LEFT" then
    frame:SetPoint("TOPRIGHT", layout, "TOPRIGHT", -row * (w + spacing), -col * (h + spacing))
  else
    frame:SetPoint("TOPLEFT", layout, "TOPLEFT", col * (w + spacing), -row * (h + spacing))
  end
end

local function SetPreservedPreviewPoint(frame, layout, index, w, h, spacing, growth, primary, blockW, blockH)
  if not primary then
    local conf = layout and layout._msufGFKind and GF.GetConf and GF.GetConf(layout._msufGFKind)
    local upc = floor((tonumber(conf and conf.unitsPerColumn) or 5) + 0.5)
    if upc < 1 then upc = 1 end
    primary = min(upc, 5)
  end
  if primary < 1 then primary = 1 end
  local blockColumns = max(1, floor((5 + primary - 1) / primary))
  blockW = blockW or (blockColumns * w + max(0, blockColumns - 1) * spacing)
  blockH = blockH or (primary * h + max(0, primary - 1) * spacing)
  local groupIndex = floor((index - 1) / 5)
  local withinGroup = (index - 1) % 5
  local minor = floor(withinGroup / primary)
  local major = withinGroup % primary
  if growth == "UP" then
    frame:SetPoint("BOTTOMLEFT", layout, "BOTTOMLEFT", groupIndex * (blockW + spacing) + minor * (w + spacing), major * (h + spacing))
  elseif growth == "RIGHT" then
    frame:SetPoint("TOPLEFT", layout, "TOPLEFT", major * (w + spacing), -(groupIndex * (blockH + spacing) + minor * (h + spacing)))
  elseif growth == "LEFT" then
    frame:SetPoint("TOPRIGHT", layout, "TOPRIGHT", -major * (w + spacing), -(groupIndex * (blockH + spacing) + minor * (h + spacing)))
  else
    frame:SetPoint("TOPLEFT", layout, "TOPLEFT", groupIndex * (blockW + spacing) + minor * (w + spacing), -major * (h + spacing))
  end
end

local function PositionPreviewFrame(frame, layout, index, kind, w, h, spacing, growth, upc, primary, blockW, blockH)
  local conf = GF.GetConf and GF.GetConf(kind) or nil
  local posKey = tostring(layout) .. "\030" .. tostring(index) .. "\030" .. tostring(kind)
    .. "\030" .. tostring(w) .. "\030" .. tostring(h) .. "\030" .. tostring(spacing)
    .. "\030" .. tostring(growth) .. "\030" .. tostring(upc) .. "\030" .. tostring(primary)
    .. "\030" .. tostring(blockW) .. "\030" .. tostring(blockH)
    .. "\030" .. tostring(conf and conf.preserveRaidGroups == true)
  if frame._msufGFPreviewPositionKey == posKey then return end
  frame._msufGFPreviewPositionKey = posKey
  frame:ClearAllPoints()
  if IsRaidLikeKind(kind) and conf and conf.preserveRaidGroups == true then
    SetPreservedPreviewPoint(frame, layout, index, w, h, spacing, growth, primary, blockW, blockH)
  else
    PlacePreviewFrame(frame, layout, index, w, h, spacing, growth, upc)
  end
end

local function PreviewApplyRevision(kind)
  if GF.GetCompiledSpecRevision then return GF.GetCompiledSpecRevision(kind) end
  return tostring(GF._compiledSpecRevision or "") .. ":" .. tostring(GF._compiledSpecSerial or "")
end

local function PreviewApplyKey(frame, kind, w, h, revision)
  local unit = (frame.GetAttribute and frame:GetAttribute("unit")) or frame.unit or "player"
  return tostring(kind) .. "\030" .. tostring(unit) .. "\030" .. tostring(revision or PreviewApplyRevision(kind))
    .. "\030" .. tostring(w) .. "\030" .. tostring(h)
end

local function ApplyPreviewSpecIfNeeded(frame, kind, reason, w, h, dirtyMask, expectedRevision)
  if not frame then return false end
  local currentRevision = PreviewApplyRevision(kind)
  local key = PreviewApplyKey(frame, kind, w, h, currentRevision)
  if frame._msufGFPreviewApplyKey == key and frame.MSUFSpec then return true end
  local revisionCurrent = expectedRevision == nil or currentRevision == expectedRevision
  local canApplyDirty = frame.MSUFSpec ~= nil
    and dirtyMask ~= nil
    and revisionCurrent
    and type(GF.ApplyPreviewButtonDirty) == "function"
  local ok
  if canApplyDirty then
    ok = GF.ApplyPreviewButtonDirty(frame, kind, reason, dirtyMask)
  elseif GF.ApplyButton then
    ok = GF.ApplyButton(frame, kind, reason)
  else
    return false
  end
  if ok then frame._msufGFPreviewApplyKey = PreviewApplyKey(frame, kind, w, h) end
  return ok
end

local function SetPreviewFrameSize(frame, w, h)
  if frame._msufGFPreviewWidth == w and frame._msufGFPreviewHeight == h
    and (not frame.GetWidth or frame:GetWidth() == w)
    and (not frame.GetHeight or frame:GetHeight() == h) then
    return
  end
  frame._msufGFPreviewWidth, frame._msufGFPreviewHeight = w, h
  frame:SetSize(w, h)
end

local function EnsurePreviewFrame(kind, index, parent)
  local frames = GF._previewFrames[kind]
  if not frames then
    frames = {}
    GF._previewFrames[kind] = frames
  end
  local frame = frames[index]
  if frame then
    frame._msufGFPreviewIndex = index
    if frame:GetParent() ~= parent then frame:SetParent(parent) end
    return frame
  end

  frame = CreateFrame("Button", "MSUF_GFPreview_" .. kind .. "_" .. index, parent, "BackdropTemplate")
  frame._msufGFIsPreviewFrame = true
  frame._msufGFPreviewIndex = index
  frame._msufGFPreviewActive = true
  frame._msufGFKind = kind
  frame._msufIsGroupFrame = true
  frame.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ("gf_" .. kind)
  frame.unit = "player"
  frame.unitKey = "player"
  if frame.SetAttribute then frame:SetAttribute("unit", "player") end
  if frame.EnableMouse then frame:EnableMouse(false) end
  if frame.RegisterForClicks then frame:RegisterForClicks("LeftButtonUp") end
  frames[index] = frame
  return frame
end

local function PreparePreviewFrame(kind, index, layout, w, h, spacing, growth, upc, primary, blockW, blockH)
  local frame = EnsurePreviewFrame(kind, index, layout)
  SetPreviewFrameSize(frame, w, h)
  frame.unit = "player"
  frame.unitKey = "player"
  if frame.SetAttribute then frame:SetAttribute("unit", "player") end
  PositionPreviewFrame(frame, layout, index, kind, w, h, spacing, growth, upc, primary, blockW, blockH)
  if not frame.MSUFSpec and frame.Hide then frame:Hide() end
  return frame
end

local function ApplyPreviewFrame(kind, index, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
  local frame = PreparePreviewFrame(kind, index, layout, w, h, spacing, growth, upc, primary, blockW, blockH)
  ApplyPreviewSpecIfNeeded(frame, kind, reason, w, h, dirtyMask, expectedRevision)
  ApplyPreviewData(frame, index, kind)
  return true
end

local function QueuePreviewBuild(kind, serial, visibleCount, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
  if not (C_Timer and C_Timer.After) then
    for i = 1, visibleCount do
      ApplyPreviewFrame(kind, i, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
    end
    return true
  end
  local index = 1
  local function Step()
    if CurrentPreviewBuildSerial(kind) ~= serial then return end
    if not (GF._previewActive and GF._previewActive[kind]) then return end
    local limit = min(visibleCount, index + PREVIEW_BUILD_SLICE_COUNT - 1)
    for i = index, limit do
      ApplyPreviewFrame(kind, i, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
    end
    index = limit + 1
    if index <= visibleCount then
      C_Timer.After(0, Step)
    end
  end
  C_Timer.After(0, Step)
  return true
end

local function PreviewSpecsCurrent(frames, visibleCount, kind, w, h, revision)
  for i = 1, visibleCount do
    local frame = frames[i]
    if not (frame and frame.MSUFSpec and frame._msufGFPreviewApplyKey == PreviewApplyKey(frame, kind, w, h, revision)) then
      return false
    end
  end
  return true
end

local function QueuePreviewDataRefresh(kind, serial, frames, visibleCount)
  if not (C_Timer and C_Timer.After) then
    for i = 1, visibleCount do ApplyPreviewData(frames[i], i, kind) end
    return true
  end
  local index = 1
  local function Step()
    if CurrentPreviewBuildSerial(kind) ~= serial then return end
    if not (GF._previewActive and GF._previewActive[kind]) then return end
    local limit = min(visibleCount, index + PREVIEW_BUILD_SLICE_COUNT - 1)
    for i = index, limit do ApplyPreviewData(frames[i], i, kind) end
    index = limit + 1
    if index <= visibleCount then C_Timer.After(0, Step) end
  end
  C_Timer.After(0, Step)
  return true
end

function GF.ShowPreview(kind, count, opts)
  if InCombat() then return false end
  if type(PreviewsAllowed) == "function" and not PreviewsAllowed() then return false end
  kind = NormalizeKind(kind) or "party"
  count = floor((tonumber(count) or DefaultPreviewCount(kind)) + 0.5)
  if count < 1 then count = DefaultPreviewCount(kind) end
  local visibleCount = VisiblePreviewCount(kind, count)
  opts = type(opts) == "table" and opts or nil

  GF._previewActive[kind] = true
  GF._previewShownCounts[kind] = count
  local serial = BumpPreviewBuildSerial(kind)

  local container, layout, w, h, spacing, growth, upc, primary, blockW, blockH = PositionContainer(kind, count)
  local frames = GF._previewFrames[kind] or {}
  GF._previewFrames[kind] = frames
  for i = 1, visibleCount do
    PreparePreviewFrame(kind, i, layout, w, h, spacing, growth, upc, primary, blockW, blockH)
  end
  for i = visibleCount + 1, #frames do
    local frame = frames[i]
    if frame then
      ClearPreviewData(frame)
      frame:Hide()
    end
  end
  container:Show()
  local reason = opts and opts.reason or "MSUF_GF_PREVIEW"
  local dirtyMask = opts and opts.dirtyMask or nil
  local expectedRevision = PreviewApplyRevision(kind)
  if PreviewSpecsCurrent(frames, visibleCount, kind, w, h, expectedRevision) then
    if opts and opts.immediate == true or visibleCount <= PREVIEW_BUILD_SLICE_THRESHOLD then
      for i = 1, visibleCount do ApplyPreviewData(frames[i], i, kind) end
    else
      QueuePreviewDataRefresh(kind, serial, frames, visibleCount)
    end
    return true
  end
  if opts and opts.immediate == true or visibleCount <= PREVIEW_BUILD_SLICE_THRESHOLD then
    for i = 1, visibleCount do
      ApplyPreviewFrame(kind, i, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
    end
  else
    QueuePreviewBuild(kind, serial, visibleCount, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
  end
  return true
end

function GF.HidePreview(kind)
  kind = NormalizeKind(kind) or "party"
  local container = GF._previewContainer[kind]
  if GF._previewActive[kind] ~= true and (not (container and container.IsShown and container:IsShown())) then
    return true
  end
  BumpPreviewBuildSerial(kind)
  GF._previewActive[kind] = nil
  GF._previewShownCounts[kind] = nil
  local frames = GF._previewFrames[kind]
  if frames then
    for i = 1, #frames do
      if frames[i] then
        ClearPreviewData(frames[i])
        frames[i]:Hide()
      end
    end
  end
  if container then container:Hide() end
  return true
end

function GF.RefreshPreviewLayout(kind, opts)
  if InCombat() then return false end
  if kind == nil then
    local any = false
    for _, activeKind in ipairs({ "party", "raid", "mythicraid" }) do
      if GF._previewActive and GF._previewActive[activeKind] then
        any = GF.RefreshPreviewLayout(activeKind, opts) or any
      end
    end
    return any
  end
  kind = NormalizeKind(kind) or "party"
  if not (GF._previewActive and GF._previewActive[kind]) then return false end
  local count = GF._previewShownCounts[kind] or DefaultPreviewCount(kind)
  opts = type(opts) == "table" and opts or nil
  return GF.ShowPreview(kind, count, {
    reason = opts and opts.reason or "MSUF_GF_PREVIEW_REFRESH",
    dirtyMask = opts and opts.dirtyMask or nil,
  })
end

GF.RefreshPreviewBox = GF.RefreshPreviewLayout

function GF.RefreshPreviewAnimation()
  if InCombat() then return false end
  local any = false
  for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
    if GF._previewActive and GF._previewActive[kind] then
      local count = GF._previewShownCounts[kind] or DefaultPreviewCount(kind)
      local visibleCount = VisiblePreviewCount(kind, count)
      local frames = GF._previewFrames[kind]
      if frames then
        for i = 1, visibleCount do
          local frame = frames[i]
          if frame and frame.IsShown and frame:IsShown() then
            ApplyPreviewData(frame, i, kind)
            any = true
          end
        end
      end
    end
  end
  return any
end

PreviewsAllowed = function()
  if _G.MSUF_UnitEditModeActive == true then return true end
  if _G.MSUF2_GFPagePreviewActive == true then return true end
  local panel = _G.MSUF_GFOptionsPanel
  return panel and panel.IsShown and panel:IsShown() or false
end

function GF.HideOrphanedPreviews()
  if PreviewsAllowed() then return false end
  local hidden = false
  for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
    if GF._previewActive[kind] then
      GF.HidePreview(kind)
      hidden = true
    end
  end
  return hidden
end

ExportPublic("MSUF_GF_ShowPreview", function(kind, count) return GF.ShowPreview(kind, count) end)
ExportPublic("MSUF_GF_HidePreview", function(kind) return GF.HidePreview(kind) end)
ExportPublic("MSUF_GF_SetPreviewAnchor", function(kind, parent) return GF.SetPreviewAnchor(kind, parent) end)
ExportPublic("MSUF_GF_RefreshPreviewLayout", function(kind, opts) return GF.RefreshPreviewLayout(kind, opts) end)
ExportPublic("MSUF_GF_RefreshPreviewBox", _G.MSUF_GF_RefreshPreviewLayout)
ExportPublic("MSUF_GF_RefreshPreviewAnimation", function() return GF.RefreshPreviewAnimation() end)
