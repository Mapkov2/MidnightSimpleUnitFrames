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
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
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
GF._previewFreeFrames = GF._previewFreeFrames or {}
GF._previewFrameSerial = tonumber(GF._previewFrameSerial) or 0

local PREVIEW_BUILD_SLICE_COUNT = 2
local PREVIEW_BUILD_SLICE_THRESHOLD = 8
local PREVIEW_KINDS = { "party", "raid", "mythicraid" }

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
  if GF.GetAnchorPoint then return GF.GetAnchorPoint(conf) end
  local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
  if not VALID_POINTS[point] then point = "CENTER" end
  return point
end

--- Both sides of a group anchor come from the single visible Anchor Point; see
--- GF.ResolveAnchorPoint (MSUF_GroupFrames_DB.lua) for the legacy pair it retires.
local function ResolveAnchorPoint(kind, conf, parent)
  if GF.ResolveAnchorPoint then return GF.ResolveAnchorPoint(kind, conf, parent) end
  local point = AnchorPoint(conf)
  return point, point
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

local function ClampPreviewOffsetOnScreen(point, relativePoint, relative, x, y, totalW, totalH)
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
  local rfx, rfy = PointFraction(relativePoint)
  local px = pLeft + (pRight - pLeft) * rfx + (x or 0)
  local py = pBottom + (pTop - pBottom) * rfy + (y or 0)
  local boxW, boxH = totalW or 0, totalH or 0
  local left = px - boxW * fx
  local bottom = py - boxH * fy
  local dx = ClampBoxAxis(left, left + boxW, screenW)
  local dy = ClampBoxAxis(bottom, bottom + boxH, screenH)
  if dx == 0 and dy == 0 then return x, y end
  return (x or 0) + dx, (y or 0) + dy
end

local function ResolveAnchorFrame(conf, owner)
  if type(GF.ResolveAnchorFrame) == "function" then
    local frame, missing = GF.ResolveAnchorFrame(conf, owner)
    if missing and type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
      _G.MSUF_ScheduleLateAnchorReanchor()
    end
    return frame
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
  if GF.EnsureStableGridPosition then
    GF.EnsureStableGridPosition(kind, posCount, conf)
  end
  local _, _, posW, posH = GF.GetGridMetrics(kind, posCount)
  local _, _, _, _, w, h, spacing, growth, upc, _, _, _, primary, _, _, blockW, blockH = GF.GetGridMetrics(kind, count)
  local parent = GF._previewAnchorFrame and GF._previewAnchorFrame[kind]
  local container, layout = EnsureContainer(kind, parent or UIParent)

  local containerW, containerH = max(posW or w or 1, 1), max(posH or h or 1, 1)
  local point, relativePoint, relative, x, y
  if parent then
    point, relativePoint, relative, x, y = "CENTER", "CENTER", parent, 0, 0
  else
    relative = ResolveAnchorFrame(conf, container)
    -- Resolving can retire a legacy relativePoint into the offsets, so read
    -- those afterwards.
    point, relativePoint = ResolveAnchorPoint(kind, conf, relative)
    local cx, cy = tonumber(conf.offsetX), tonumber(conf.offsetY)
    if cx == nil or cy == nil then cx, cy = DefaultCenter(kind) end
    x, y = floor(cx + 0.5), floor(cy + 0.5)
  end
  if GF.ConfigureAnchorPointScreenClamp then
    GF.ConfigureAnchorPointScreenClamp(container, point, containerW, containerH)
  else
    x, y = ClampPreviewOffsetOnScreen(point, relativePoint, relative, x, y, containerW, containerH)
  end
  local containerKey = tostring(point) .. "\030" .. tostring(relativePoint) .. "\030" .. tostring(relative) .. "\030" .. tostring(x) .. "\030" .. tostring(y)
    .. "\030" .. tostring(containerW) .. "\030" .. tostring(containerH)
  if container._msufGFPreviewPositionKey ~= containerKey then
    container._msufGFPreviewPositionKey = containerKey
    container:ClearAllPoints()
    container:SetSize(containerW, containerH)
    container:SetPoint(point, relative, relativePoint, x, y)
  end

  local layoutW, layoutH = containerW, containerH
  local layoutPoint = AnchorPoint(conf)
  local layoutKey = tostring(layoutPoint) .. "\030" .. tostring(layoutW) .. "\030" .. tostring(layoutH)
    .. "\030" .. tostring(container)
  if layout._msufGFPreviewPositionKey ~= layoutKey then
    layout._msufGFPreviewPositionKey = layoutKey
    layout:ClearAllPoints()
    layout:SetSize(layoutW, layoutH)
    --- The preview layout already has the full grid footprint. Align it with
    --- the logical container instead of applying the header-origin delta a
    --- second time; this keeps preview and live bounds count-independent.
    layout:SetPoint(layoutPoint, container, layoutPoint, 0, 0)
  end
  layout.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ("gf_" .. kind)
  layout._msufIsGroupFrame = true
  layout._msufGFKind = kind
  layout._msufGFPreviewLayout = true
  layout._msufGFDragCenterToGridX = 0
  layout._msufGFDragCenterToGridY = 0
  --- The live block border is drawn on the header anchor, which the preview
  --- replaces. Re-draw it on the container (same footprint) or the setting
  --- stays invisible for as long as a preview is up.
  if type(GF.ApplyGroupBorderToFrame) == "function" then
    GF.ApplyGroupBorderToFrame(container, conf)
  end
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

--- Native aura elements deliberately stay disabled on synthetic group-preview
--- rows because each Blizzard CustomAuraContainer allocates AuraButtons in
--- batches and can only show the real player's current auras. These tiny
--- addon-owned regions mirror only already-compiled aura/spell placement data
--- on every Party/Raid/Mythic dummy. They are pooled with the preview button,
--- never query UnitAura, and never register an event or OnUpdate.
local PREVIEW_WHITE = "Interface\\Buttons\\WHITE8X8"
local PREVIEW_QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local PREVIEW_AURA_SAMPLE_LIMIT = 2
local PREVIEW_AURA_LANES = {
  {
    key = "buff",
    textures = {
      "Interface\\Icons\\Spell_Holy_WordFortitude",
      "Interface\\Icons\\Spell_Holy_Renew",
    },
  },
  {
    key = "trackedBuff",
    textures = {
      "Interface\\Icons\\Spell_Holy_PrayerOfMendingtga",
      "Interface\\Icons\\Spell_Holy_PowerWordShield",
    },
  },
  {
    key = "debuff",
    textures = {
      "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
      "Interface\\Icons\\Spell_Shadow_AbominationExplosion",
    },
  },
  {
    key = "external",
    textures = {
      "Interface\\Icons\\Spell_Holy_SealOfProtection",
      "Interface\\Icons\\Spell_Holy_PowerWordShield",
    },
  },
}

local function SetPreviewFont(fontString, size)
  if not (fontString and fontString.SetFont) then return end
  size = max(6, tonumber(size) or 10)
  if fontString._msufGFPreviewFontSize == size then return end
  fontString._msufGFPreviewFontSize = size
  fontString:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
end

local function PlacePreviewText(fontString, owner, point, x, y)
  if not (fontString and owner) then return end
  point = tostring(point or "CENTER"):upper()
  if not VALID_POINTS[point] then point = "CENTER" end
  fontString:ClearAllPoints()
  fontString:SetPoint(point, owner, point, tonumber(x) or 0, tonumber(y) or 0)
end

local function EnsureSpellIndicatorPreview(frame, index)
  local pool = frame._msufGFSpellIndicatorPreviews
  if not pool then
    pool = {}
    frame._msufGFSpellIndicatorPreviews = pool
  end
  local visual = pool[index]
  if visual then return visual end

  visual = CreateFrame("Frame", nil, frame)
  visual:EnableMouse(false)
  if visual.SetMouseMotionEnabled then visual:SetMouseMotionEnabled(false) end
  visual._texture = visual:CreateTexture(nil, "ARTWORK")
  visual._texture:SetAllPoints(visual)
  pool[index] = visual
  return visual
end

local function EnsurePreviewTexture(visual, key, layer, sublevel)
  local texture = visual[key]
  if not texture then
    texture = visual:CreateTexture(nil, layer, nil, sublevel)
    visual[key] = texture
  end
  return texture
end

local function EnsurePreviewFontString(visual, key)
  local fontString = visual[key]
  if not fontString then
    fontString = visual:CreateFontString(nil, "OVERLAY")
    visual[key] = fontString
  end
  return fontString
end

local function EnsureFrameAuraPreview(frame, index)
  local pool = frame._msufGFFrameAuraPreviews
  if not pool then
    pool = {}
    frame._msufGFFrameAuraPreviews = pool
  end
  local visual = pool[index]
  if visual then return visual end

  visual = CreateFrame("Frame", nil, frame)
  visual:EnableMouse(false)
  if visual.SetMouseMotionEnabled then visual:SetMouseMotionEnabled(false) end
  visual._texture = visual:CreateTexture(nil, "ARTWORK")
  visual._texture:SetAllPoints(visual)
  pool[index] = visual
  return visual
end

local function EnsureFrameAuraLaneHost(frame, key)
  local hosts = frame._msufGFFrameAuraPreviewHosts
  if not hosts then
    hosts = {}
    frame._msufGFFrameAuraPreviewHosts = hosts
  end
  local host = hosts[key]
  if host then return host end
  host = CreateFrame("Frame", nil, frame)
  host:EnableMouse(false)
  if host.SetMouseMotionEnabled then host:SetMouseMotionEnabled(false) end
  hosts[key] = host
  return host
end

local function HideFrameAuraPreview(visual)
  if not visual then return end
  visual:Hide()
  if visual._texture then visual._texture:Hide() end
  if visual._swipe then visual._swipe:Hide() end
  if visual._timer then visual._timer:Hide() end
  if visual._stack then visual._stack:Hide() end
  if visual._durationBar then visual._durationBar:Hide() end
  local A3 = MSUF and MSUF.MSUF_Auras3
  if A3 and type(A3.ApplyIconStylePreview) == "function" then
    A3.ApplyIconStylePreview(visual, nil)
  end
end

local function FrameAuraPreviewOffset(lane, slot)
  local step = tonumber(lane.step) or ((tonumber(lane.size) or 1) + (tonumber(lane.spacing) or 0))
  if lane.verticalGrowth == true then
    return 0, slot * step * (tonumber(lane.ySign) or -1)
  end
  local perRow = max(1, floor((tonumber(lane.perRow) or 1) + 0.5))
  local column = slot % perRow
  local row = floor(slot / perRow)
  local x = column * step * (tonumber(lane.xSign) or 1)
  local y = row * step * (tonumber(lane.ySign) or -1)
  return x, y
end

local function ApplyFrameAuraPreview(frame, kind, visual, lane, descriptor, slot, sampleIndex, host)
  local size = max(1, tonumber(lane.size) or 18)
  local initialAnchor = tostring(lane.initialAnchor or "TOPLEFT"):upper()
  if not VALID_POINTS[initialAnchor] then initialAnchor = "TOPLEFT" end
  local x, y = FrameAuraPreviewOffset(lane, slot)

  visual:ClearAllPoints()
  visual:SetSize(size, size)
  visual:SetPoint(initialAnchor, host, initialAnchor, x, y)
  if visual.SetFrameLevel and host.GetFrameLevel then visual:SetFrameLevel((host:GetFrameLevel() or 0) + 1) end
  if visual.SetAlpha then visual:SetAlpha(1) end

  local texture = visual._texture
  local textures = descriptor.textures
  texture:SetTexture(textures[((sampleIndex - 1) % #textures) + 1] or PREVIEW_QUESTION)
  local zoom = max(100, min(200, tonumber(lane.iconZoom) or 100))
  local inset = (1 - (100 / zoom)) * 0.5
  texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
  texture:SetVertexColor(1, 1, 1, 1)

  local swipe, timer, stack, durationBar, dispelBorder = visual._swipe, visual._timer,
    visual._stack, visual._durationBar, visual._dispelBorder
  if swipe then swipe:Hide() end
  if timer then timer:Hide() end
  if stack then stack:Hide() end
  if durationBar then durationBar:Hide() end
  if dispelBorder then dispelBorder:Hide() end
  local barOnly = lane.showDurationBar == true and lane.durationBarDisplay == "BAR_ONLY"
  texture:SetShown(not barOnly)

  if lane.showCooldownSwipe == true and not barOnly then
    swipe = EnsurePreviewTexture(visual, "_swipe", "OVERLAY", 1)
    swipe:ClearAllPoints()
    swipe:SetPoint("TOPLEFT", visual, "TOPLEFT", 0, 0)
    swipe:SetPoint("BOTTOMRIGHT", visual, "BOTTOMRIGHT", 0, size * 0.42)
    swipe:SetTexture(PREVIEW_WHITE)
    swipe:SetVertexColor(0, 0, 0, 0.58)
    swipe:Show()
  end

  if lane.showCooldownText == true then
    timer = EnsurePreviewFontString(visual, "_timer")
    SetPreviewFont(timer, lane.cooldownSize or 8)
    timer:SetText(sampleIndex == 1 and "12" or "8")
    timer:SetTextColor(1, 1, 1, 1)
    PlacePreviewText(timer, visual, lane.cooldownAnchor or "CENTER", lane.cooldownX or 0, lane.cooldownY or 0)
    timer:Show()
  end

  if lane.showStacks == true then
    stack = EnsurePreviewFontString(visual, "_stack")
    SetPreviewFont(stack, lane.stackSize or 10)
    stack:SetText("2")
    local A3 = MSUF and MSUF.MSUF_Auras3
    local r, g, b
    if A3 and type(A3._StackCountColor) == "function" then r, g, b = A3._StackCountColor() end
    stack:SetTextColor(r or 1, g or 1, b or 1, 1)
    PlacePreviewText(stack, visual, lane.stackAnchor or "BOTTOMRIGHT", lane.stackX or 0, lane.stackY or 0)
    stack:Show()
  end

  if lane.showDurationBar == true then
    durationBar = EnsurePreviewTexture(visual, "_durationBar", "OVERLAY", 2)
    local height = max(1, min(size, tonumber(lane.durationBarHeight) or 2))
    durationBar:ClearAllPoints()
    if lane.durationBarPosition == "TOP" then
      durationBar:SetPoint("TOPLEFT", visual, "TOPLEFT", 1, -1)
      durationBar:SetPoint("TOPRIGHT", visual, "TOPRIGHT", -1, -1)
    else
      durationBar:SetPoint("BOTTOMLEFT", visual, "BOTTOMLEFT", 1, 1)
      durationBar:SetPoint("BOTTOMRIGHT", visual, "BOTTOMRIGHT", -1, 1)
    end
    durationBar:SetHeight(height)
    durationBar:SetTexture(PREVIEW_WHITE)
    local A3 = MSUF and MSUF.MSUF_Auras3
    local r, g, b
    if A3 and type(A3.GetDurationBarColor) == "function" then r, g, b = A3.GetDurationBarColor() end
    durationBar:SetVertexColor(r or 1, g or 1, b or 1, 1)
    durationBar:Show()
  end

  local A3 = MSUF and MSUF.MSUF_Auras3
  if A3 and type(A3.ApplyAuraIconShape) == "function" then
    A3.ApplyAuraIconShape(visual, lane.iconShape, nil, texture, swipe)
  end
  if A3 and type(A3.ApplyIconStylePreview) == "function" then
    A3.ApplyIconStylePreview(visual, barOnly and nil or lane.iconStyle, size, lane.iconShape)
  end
  if lane.showAuraBorder == true and not barOnly then
    dispelBorder = EnsurePreviewTexture(visual, "_dispelBorder", "OVERLAY", 5)
    if A3 and type(A3.ApplyAuraDispelPreview) == "function"
      and A3.ApplyAuraDispelPreview(dispelBorder, visual, size,
        lane.showAuraSymbol == true and "SYMBOL" or "BORDER", lane.iconShape,
        A3.PreviewDispelTypeForIndex(sampleIndex)) then
      -- Shared renderer stamped the matching shaped/rounded border.
    elseif dispelBorder.SetAtlas then
      local pad = type(A3.NativeAuraDispelBorderPadding) == "function"
        and A3.NativeAuraDispelBorderPadding(size)
        or max(1, floor(size / 6 + 0.5))
      dispelBorder:ClearAllPoints()
      dispelBorder:SetPoint("TOPLEFT", visual, "TOPLEFT", -pad, pad)
      dispelBorder:SetPoint("BOTTOMRIGHT", visual, "BOTTOMRIGHT", pad, -pad)
      dispelBorder:SetAtlas(lane.showAuraSymbol == true
        and "ui-debuff-border-magic-icon" or "ui-debuff-border-magic-noicon", false)
    else
      dispelBorder:ClearAllPoints()
      dispelBorder:SetAllPoints(visual)
      dispelBorder:SetTexture(PREVIEW_WHITE)
      dispelBorder:SetVertexColor(0.2, 0.6, 1, 0.85)
    end
    dispelBorder:Show()
  end
  visual:Show()
  return true
end

function GF.HideFrameAuras(frame)
  local pool = frame and frame._msufGFFrameAuraPreviews
  if pool then
    for i = 1, #pool do HideFrameAuraPreview(pool[i]) end
  end
  local hosts = frame and frame._msufGFFrameAuraPreviewHosts
  if hosts then
    for _, host in pairs(hosts) do host:Hide() end
  end
  return pool ~= nil or hosts ~= nil
end

function GF.PreviewFrameAuras(frame, kind, previewIndex, compiledAuras, compiledSpec)
  if InCombat() then return false end
  local spec = frame and frame.MSUFSpec
  local auras = compiledAuras or (spec and spec.auras)
  if not (auras and auras.enabled == true) then
    GF.HideFrameAuras(frame)
    return false
  end

  local A3 = MSUF and MSUF.MSUF_Auras3
  local runtimeConfig = A3 and type(A3.ResolveAuraPreviewConfig) == "function"
    and A3.ResolveAuraPreviewConfig(frame, frame.MSUFUnitKey, compiledSpec) or nil
  local lanes = runtimeConfig and runtimeConfig.lanes
  if not lanes then
    GF.HideFrameAuras(frame)
    return false
  end

  local used = 0
  previewIndex = max(1, floor((tonumber(previewIndex) or 1) + 0.5))
  for laneIndex = 1, #PREVIEW_AURA_LANES do
    local descriptor = PREVIEW_AURA_LANES[laneIndex]
    local lane = lanes[descriptor.key]
    local maxCount = max(0, floor((tonumber(lane and lane.max) or 0) + 0.5))
    local host = EnsureFrameAuraLaneHost(frame, descriptor.key)
    if lane and lane.enabled == true and maxCount > 0 then
      local anchor = tostring(lane.anchor or "CENTER"):upper()
      if not VALID_POINTS[anchor] then anchor = "CENTER" end
      host:ClearAllPoints()
      host:SetPoint(anchor, frame, anchor, tonumber(lane.x) or 0, tonumber(lane.y) or 0)
      host:SetSize(max(1, tonumber(lane.width) or lane.size or 1),
        max(1, tonumber(lane.height) or lane.size or 1))
      if host.SetFrameLevel and frame.GetFrameLevel then
        local layers = MSUF and MSUF.UF and MSUF.UF.Layers or {}
        host:SetFrameLevel(layers.ElementLevel and layers.ElementLevel(lane.layer, 1, 0)
          or ((frame:GetFrameLevel() or 0) + (tonumber(lane.layer) or 1)))
      end
      if host.SetAlpha then host:SetAlpha(tonumber(lane.alpha) or 1) end
      host:Show()
      local sampleCount = min(PREVIEW_AURA_SAMPLE_LIMIT, maxCount)
      for sampleIndex = 1, sampleCount do
        used = used + 1
        ApplyFrameAuraPreview(frame, kind, EnsureFrameAuraPreview(frame, used),
          lane, descriptor, sampleIndex - 1, sampleIndex + previewIndex + laneIndex, host)
      end
    else
      host:Hide()
    end
  end
  local pool = frame._msufGFFrameAuraPreviews
  for i = used + 1, pool and #pool or 0 do HideFrameAuraPreview(pool[i]) end
  return used > 0
end

--- Refresh only the pooled Aura stand-ins on active Edit Mode group dummies.
--- Menu sliders use this path while dragging so raw DB geometry reaches the
--- dummy frames immediately without reapplying live frames or rebuilding the
--- rest of each preview button. No preview survives combat, and the hard guard
--- keeps this entry point inert even if an external caller races combat entry.
function GF.RefreshPreviewAuras(kind)
  if InCombat() then return false end
  if kind == nil then
    local any = false
    for i = 1, #PREVIEW_KINDS do
      local activeKind = PREVIEW_KINDS[i]
      if GF._previewActive and GF._previewActive[activeKind] then
        any = GF.RefreshPreviewAuras(activeKind) or any
      end
    end
    return any
  end
  kind = NormalizeKind(kind)
  if not kind then return false end
  if type(GF.InvalidateCompiledSpecs) == "function" then GF.InvalidateCompiledSpecs(kind) end
  if not (GF._previewActive and GF._previewActive[kind]) then return false end
  local compile = GF.GetCompiledSpec or GF.CompileSpec
  local spec = type(compile) == "function" and compile(kind) or nil
  local auras = spec and spec.auras
  local frames = GF._previewFrames and GF._previewFrames[kind]
  if not (auras and frames) then return false end

  local refreshed = false
  for i = 1, #frames do
    local frame = frames[i]
    if frame and frame.IsShown and frame:IsShown() then
      GF.PreviewFrameAuras(frame, kind, i, auras, spec)
      refreshed = true
    end
  end
  return refreshed
end

local function HideSpellIndicatorPreview(visual)
  if not visual then return end
  visual:Hide()
  if visual._glow then visual._glow:Hide() end
  if visual._texture then visual._texture:Hide() end
  if visual._swipe then visual._swipe:Hide() end
  if visual._timer then visual._timer:Hide() end
  if visual._stack then visual._stack:Hide() end
  if visual._durationBar then visual._durationBar:Hide() end
  local effectRoot = visual._frameEffectRoot
  if effectRoot then
    if effectRoot._tint then effectRoot._tint:Hide() end
    if effectRoot._name then effectRoot._name:Hide() end
    for i = 1, #(effectRoot._edges or {}) do effectRoot._edges[i]:Hide() end
    effectRoot:Hide()
  end
  local A3 = MSUF and MSUF.MSUF_Auras3
  if A3 and type(A3.ApplyIconStylePreview) == "function" then
    A3.ApplyIconStylePreview(visual, nil)
  end
end

local function EnsureSpellFrameEffectPreview(visual, frame)
  local root = visual._frameEffectRoot
  if root then return root end
  root = CreateFrame("Frame", nil, frame)
  root:EnableMouse(false)
  if root.SetMouseMotionEnabled then root:SetMouseMotionEnabled(false) end
  root._tint = root:CreateTexture(nil, "OVERLAY")
  root._tint:SetTexture(PREVIEW_WHITE)
  root._edges = {}
  for i = 1, 4 do
    root._edges[i] = root:CreateTexture(nil, "OVERLAY")
    root._edges[i]:SetTexture(PREVIEW_WHITE)
  end
  root._name = root:CreateFontString(nil, "OVERLAY")
  visual._frameEffectRoot = root
  return root
end

local function ApplySpellFrameEffectPreview(visual, frame, slot)
  local effect = slot and slot.frameEffect
  local effectKind = type(effect) == "table" and tostring(effect.type or "none"):lower() or "none"
  if effectKind ~= "healthtint" and effectKind ~= "border" and effectKind ~= "glow"
    and effectKind ~= "pulse" and effectKind ~= "namecolor" then
    local root = visual._frameEffectRoot
    if root then
      if root._tint then root._tint:Hide() end
      if root._name then root._name:Hide() end
      for i = 1, #(root._edges or {}) do root._edges[i]:Hide() end
      root:Hide()
    end
    return false
  end

  local health = frame and (frame.hpBar or frame.Health or frame.health)
  local target = health and health.GetStatusBarTexture and health:GetStatusBarTexture()
  local nameSource = frame and (frame.Name or frame.name or frame.NameText or frame.nameText or frame._nameFS)
  if (effectKind == "namecolor" and not nameSource)
    or (effectKind ~= "namecolor" and not (health and target)) then
    return false
  end

  local root = EnsureSpellFrameEffectPreview(visual, frame)
  root:ClearAllPoints()
  root:SetAllPoints(health or frame)
  local layers = MSUF and MSUF.UF and MSUF.UF.Layers or {}
  if root.SetFrameLevel and frame.GetFrameLevel then
    local priority = max(1, min(10, tonumber(effect.priority) or 5))
    local targetOwner = health
    if effectKind == "namecolor" then
      targetOwner = nameSource and nameSource.GetParent and nameSource:GetParent() or frame
    end
    root:SetFrameLevel(layers.AuraEffectLevel and layers.AuraEffectLevel(effect.layer, priority, targetOwner)
      or layers.ElementLevel and layers.ElementLevel(effect.layer, 0,
      11 - priority)
      or ((frame:GetFrameLevel() or 0)
        + (tonumber(layers.SPELL_FRAME_EFFECT_BASE_OFFSET) or 1)
        + (11 - priority)
        + max(0, min(30, tonumber(effect.layer) or 0))))
  end
  root._tint:Hide()
  root._name:Hide()
  for i = 1, #root._edges do root._edges[i]:Hide() end

  local color = type(effect.color) == "table" and effect.color or {}
  local r, g, b, a = tonumber(color[1]) or 1, tonumber(color[2]) or 1,
    tonumber(color[3]) or 1, tonumber(color[4]) or 1
  if effectKind == "healthtint" then
    root._tint:ClearAllPoints()
    root._tint:SetAllPoints(target)
    if root._tint.SetBlendMode then root._tint:SetBlendMode("BLEND") end
    root._tint:SetVertexColor(r, g, b, tonumber(effect.tintAlpha) or a)
    root._tint:Show()
  elseif effectKind == "namecolor" then
    local name = root._name
    local font, fontSize, flags
    if nameSource.GetFont then font, fontSize, flags = nameSource:GetFont() end
    if font and fontSize then name:SetFont(font, fontSize, flags) end
    name:ClearAllPoints()
    name:SetAllPoints(nameSource)
    name:SetText(nameSource.GetText and nameSource:GetText() or "")
    name:SetTextColor(r, g, b, a)
    name:Show()
  else
    local thickness = max(1, min(32, tonumber(effect.thickness) or (effectKind == "glow" and 3 or 2)))
    if effectKind == "glow" then thickness = thickness + 2 end
    local top, bottom, left, right = root._edges[1], root._edges[2], root._edges[3], root._edges[4]
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", target, "TOPLEFT", -thickness, thickness)
    top:SetPoint("TOPRIGHT", target, "TOPRIGHT", thickness, thickness)
    top:SetHeight(thickness)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -thickness, -thickness)
    bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", thickness, -thickness)
    bottom:SetHeight(thickness)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")
    left:SetWidth(thickness)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
    right:SetWidth(thickness)
    local edgeAlpha = effectKind == "glow" and min(1, a + 0.16)
      or (effectKind == "pulse" and a * 0.72 or a)
    for i = 1, 4 do
      root._edges[i]:SetVertexColor(r, g, b, edgeAlpha)
      root._edges[i]:Show()
    end
  end
  root:Show()
  return true
end

local function ApplySpellIndicatorPreview(frame, kind, visual, slot)
  local visualType = slot and tostring(slot.visual or "none"):lower() or "none"
  local hiddenVisual = slot and slot.hiddenVisual == true
  local effectShown = ApplySpellFrameEffectPreview(visual, frame, slot)
  if not slot or (visualType == "none" and not effectShown) then
    HideSpellIndicatorPreview(visual)
    return false
  end

  local size = max(1, tonumber(slot.size) or 18)
  local width = max(1, tonumber(slot.width) or size)
  local height = max(1, tonumber(slot.height) or size)
  local anchor = tostring(slot.anchor or "TOPLEFT"):upper()
  if not VALID_POINTS[anchor] then anchor = "TOPLEFT" end
  visual:ClearAllPoints()
  visual:SetSize(width, height)
  visual:SetPoint(anchor, frame, anchor, tonumber(slot.x) or 0, tonumber(slot.y) or 0)
  if visual.SetFrameLevel and frame.GetFrameLevel then
    local layers = MSUF and MSUF.UF and MSUF.UF.Layers or {}
    visual:SetFrameLevel(layers.ElementLevel and layers.ElementLevel(slot.layer, 9, 1)
      or ((frame:GetFrameLevel() or 0) + (tonumber(slot.layer) or 9)))
  end

  local color = type(slot.color) == "table" and slot.color or nil
  local r = tonumber(color and color[1]) or 0.69
  local g = tonumber(color and color[2]) or 0.50
  local b = tonumber(color and color[3]) or 0.88
  local a = tonumber(color and color[4]) or 1
  local texture = visual._texture
  local swipe, timer, stack, glow, durationBar = visual._swipe, visual._timer,
    visual._stack, visual._glow, visual._durationBar
  local A3 = MSUF and MSUF.MSUF_Auras3
  texture:ClearAllPoints()
  texture:SetAllPoints(visual)
  if swipe then swipe:Hide() end
  if timer then timer:Hide() end
  if stack then stack:Hide() end
  if glow then glow:Hide() end
  if durationBar then durationBar:Hide() end
  if visualType ~= "icon" and A3 and type(A3.ApplyIconStylePreview) == "function" then
    A3.ApplyIconStylePreview(visual, nil)
  end

  local barOnly = slot.showDurationBar == true and slot.durationBarDisplay == "BAR_ONLY"
  if hiddenVisual then
    texture:Hide()
  elseif visualType == "bar" then
    texture:SetTexture(PREVIEW_WHITE)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(r * 0.18, g * 0.18, b * 0.18, a * 0.55)
    texture:Show()
    durationBar = EnsurePreviewTexture(visual, "_durationBar", "OVERLAY", 2)
    durationBar:ClearAllPoints()
    local edge = slot.durationBarReverseFill == true and "RIGHT" or "LEFT"
    durationBar:SetPoint("TOP" .. edge, visual, "TOP" .. edge, 0, 0)
    durationBar:SetPoint("BOTTOM" .. edge, visual, "BOTTOM" .. edge, 0, 0)
    durationBar:SetWidth(max(1, width * 0.68))
    durationBar:SetTexture(PREVIEW_WHITE)
    durationBar:SetVertexColor(r, g, b, a)
    durationBar:Show()
    if slot.showCooldownText == true then
      timer = EnsurePreviewFontString(visual, "_timer")
      SetPreviewFont(timer, slot.cooldownSize or 8)
      timer:SetText("12")
      timer:SetTextColor(1, 1, 1, 1)
      PlacePreviewText(timer, visual, slot.cooldownAnchor or "CENTER", slot.cooldownX or 0, slot.cooldownY or 0)
      timer:Show()
    end
  elseif visualType == "square" then
    texture:SetTexture(PREVIEW_WHITE)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(r, g, b, a)
    texture:Show()
  elseif visualType == "number" then
    texture:Hide()
    stack = EnsurePreviewFontString(visual, "_stack")
    SetPreviewFont(stack, size * 0.72)
    stack:SetText("2")
    stack:SetTextColor(r, g, b, a)
    PlacePreviewText(stack, visual, "CENTER", 0, 0)
    stack:Show()
  else
    texture:SetTexture(slot.icon or PREVIEW_QUESTION)
    local zoom = max(100, min(200, tonumber(slot.iconZoom) or 100))
    local inset = (1 - (100 / zoom)) * 0.5
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetShown(not barOnly)

    if slot.showCooldownSwipe == true and not barOnly then
      swipe = EnsurePreviewTexture(visual, "_swipe", "OVERLAY", 1)
      swipe:ClearAllPoints()
      swipe:SetPoint("TOPLEFT", visual, "TOPLEFT", 0, 0)
      swipe:SetPoint("BOTTOMRIGHT", visual, "BOTTOMRIGHT", 0, size * 0.42)
      swipe:SetTexture(PREVIEW_WHITE)
      swipe:SetVertexColor(0, 0, 0, 0.58)
      swipe:Show()
    end

    if slot.showCooldownText == true then
      timer = EnsurePreviewFontString(visual, "_timer")
      SetPreviewFont(timer, slot.cooldownSize or 8)
      timer:SetText("12")
      timer:SetTextColor(1, 1, 1, 1)
      PlacePreviewText(timer, visual, slot.cooldownAnchor or "CENTER", slot.cooldownX or 0, slot.cooldownY or 0)
      timer:Show()
    end

    if slot.showStacks == true then
      stack = EnsurePreviewFontString(visual, "_stack")
      SetPreviewFont(stack, slot.stackSize or 10)
      stack:SetText("2")
      local sr, sg, sb
      if A3 and type(A3._StackCountColor) == "function" then sr, sg, sb = A3._StackCountColor() end
      stack:SetTextColor(sr or 1, sg or 1, sb or 1, 1)
      PlacePreviewText(stack, visual, slot.stackAnchor or "BOTTOMRIGHT", slot.stackX or 0, slot.stackY or 0)
      stack:Show()
    end

    if slot.showDurationBar == true then
      durationBar = EnsurePreviewTexture(visual, "_durationBar", "OVERLAY", 2)
      durationBar:ClearAllPoints()
      if slot.durationBarPosition == "TOP" then
        durationBar:SetPoint("TOPLEFT", visual, "TOPLEFT", 1, -1)
        durationBar:SetPoint("TOPRIGHT", visual, "TOPRIGHT", -1, -1)
      else
        durationBar:SetPoint("BOTTOMLEFT", visual, "BOTTOMLEFT", 1, 1)
        durationBar:SetPoint("BOTTOMRIGHT", visual, "BOTTOMRIGHT", -1, 1)
      end
      durationBar:SetHeight(max(1, min(size, tonumber(slot.durationBarHeight) or 2)))
      durationBar:SetTexture(PREVIEW_WHITE)
      local dr, dg, db
      if A3 and type(A3.GetDurationBarColor) == "function" then dr, dg, db = A3.GetDurationBarColor() end
      durationBar:SetVertexColor(dr or 1, dg or 1, db or 1, 1)
      durationBar:Show()
    end

    if A3 and type(A3.ApplyIconStylePreview) == "function" then
      A3.ApplyIconStylePreview(visual, barOnly and nil or slot.iconStyle, size)
    end
  end

  if slot.iconEffect == "glow" and visualType == "icon" and not barOnly then
    glow = EnsurePreviewTexture(visual, "_glow", "BACKGROUND", -1)
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", visual, "TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", visual, "BOTTOMRIGHT", 2, -2)
    glow:SetTexture(PREVIEW_WHITE)
    glow:SetVertexColor(r, g, b, min(0.55, a))
    glow:Show()
  end
  visual:SetShown(not hiddenVisual)
  return not hiddenVisual or effectShown
end

function GF.HideSpellIndicators(frame)
  local pool = frame and frame._msufGFSpellIndicatorPreviews
  if not pool then return false end
  for i = 1, #pool do HideSpellIndicatorPreview(pool[i]) end
  return true
end

function GF.PreviewSpellIndicators(frame, kind, compiledSpec)
  if InCombat() then return false end
  local A3 = MSUF and MSUF.MSUF_Auras3
  local runtimeConfig = A3 and type(A3.ResolveAuraPreviewConfig) == "function"
    and A3.ResolveAuraPreviewConfig(frame, frame and frame.MSUFUnitKey, compiledSpec) or nil
  local root = runtimeConfig and runtimeConfig.spellIndicators
  local slots = root and root.slots
  if not (root and root.enabled == true and type(slots) == "table") then
    GF.HideSpellIndicators(frame)
    return false
  end

  local used = 0
  for i = 1, #slots do
    local slot = slots[i]
    if slot and slot.enabled == true then
      used = used + 1
      ApplySpellIndicatorPreview(frame, kind, EnsureSpellIndicatorPreview(frame, used), slot)
    end
  end
  local pool = frame._msufGFSpellIndicatorPreviews
  for i = used + 1, pool and #pool or 0 do HideSpellIndicatorPreview(pool[i]) end
  return used > 0
end

--- Refresh only pooled Spell Indicator stand-ins on active Edit Mode dummies.
--- This is a configuration/preview cold path: no aura queries, subscriptions,
--- timers, or idle scripts are installed, and combat exits before invalidation.
function GF.RefreshPreviewSpellIndicators(kind)
  if InCombat() then return false end
  if kind == nil then
    local any = false
    for i = 1, #PREVIEW_KINDS do
      local activeKind = PREVIEW_KINDS[i]
      if GF._previewActive and GF._previewActive[activeKind] then
        any = GF.RefreshPreviewSpellIndicators(activeKind) or any
      end
    end
    return any
  end
  kind = NormalizeKind(kind)
  if not kind then return false end
  local spellIndicators = GF.SpellIndicators
  if spellIndicators and type(spellIndicators.InvalidateRuntimeCaches) == "function" then
    spellIndicators.InvalidateRuntimeCaches()
  end
  if type(GF.InvalidateCompiledSpecs) == "function" then GF.InvalidateCompiledSpecs(kind) end
  if not (GF._previewActive and GF._previewActive[kind]) then return false end
  local compile = GF.GetCompiledSpec or GF.CompileSpec
  local spec = type(compile) == "function" and compile(kind) or nil
  local frames = GF._previewFrames and GF._previewFrames[kind]
  if not (spec and frames) then return false end

  local refreshed = false
  for i = 1, #frames do
    local frame = frames[i]
    if frame and frame.IsShown and frame:IsShown() then
      GF.PreviewSpellIndicators(frame, kind, spec)
      refreshed = true
    end
  end
  return refreshed
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

local function SetBar(bar, value, maxValue, animate, r, g, b, a)
  if not bar then return end
  if bar.SetMinMaxValues then bar:SetMinMaxValues(0, maxValue or 100) end
  if bar.SetValue then bar:SetValue(value or 0, animate == true and bar._msufSmoothInterp or nil) end
  if bar.SetStatusBarColor then bar:SetStatusBarColor(r or 1, g or 1, b or 1, a or 1) end
  if bar.Show then bar:Show() end
end

local function ClassColor(class)
  local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
  if type(fastClass) == "function" then
    local r, g, b = fastClass(class)
    if r then return r, g, b end
  end
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

local function ApplyPreviewText(frame, hp, hpMax, power, powerMax, class)
  local text = MSUF and MSUF.UFText
  local rt = frame and frame._msufTextRuntime
  if not (text and rt and text.UpdateTextSlots) then return end

  rt.healthMissing = max(0, (hpMax or 0) - (hp or 0))
  text.UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.MSUFUnitKey, PercentFactory((hp / max(hpMax, 1)) * 100), rt.healthNeedsPercent, rt)
  if rt.healthColorByClass == true and text.SetHealthTextColor then
    local r, g, b = ClassColor(class)
    text.SetHealthTextColor(frame, rt, r, g, b, rt.healthTextAlpha or rt.textColorA or 1)
  elseif rt.healthColorByHealth == true and text.UpdateHealthTextColor then
    text.UpdateHealthTextColor(frame, rt, frame.MSUFUnitKey, hp, hpMax)
  end

  text.UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.MSUFUnitKey, PercentFactory((power / max(powerMax, 1)) * 100), rt.powerNeedsPercent, rt)
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
  --- The compiled status always carries a raidGroup table, so gate on its
  --- enabled flag: testing the table alone kept a stale number on screen after
  --- the setting was switched off.
  local raidGroupCfg = frame.MSUFSpec and frame.MSUFSpec.status and frame.MSUFSpec.status.raidGroup
  if frame.raidGroupNameText and raidGroupCfg and raidGroupCfg.enabled == true then
    frame.raidGroupNameText:SetText(RaidGroupPreviewText(raidGroupCfg.style, ((index - 1) % 5) + 1))
    frame.raidGroupNameText:Show()
  else
    SetShown(frame.raidGroupNameText, false)
  end
  SetShown(frame.combatStateIndicatorIcon, false)
  SetShown(frame.statusIndicatorText, false)
  SetShown(frame.statusAFKTimerText, false)
end

--- Seed fake unit state into one preview frame after UF.ApplySpec has built the
--- regions. Keep this data fake/local; live group frames own real roster state.
local function ApplyPreviewData(frame, index, kind)
  if InCombat() then return false end
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
    local r, g, b = PreviewNameColor(kind, class)
    local a = GF.ResolveFontTextAlpha and GF.ResolveFontTextAlpha(kind) or 1
    frame.nameText:SetTextColor(r, g, b, a)
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
  SetBar(frame.hpBar or frame.Health or frame.health, hp, hpMax, true, PreviewHealthColor(frame, class, hpPct))

  local powerMax = 100
  local power = min(powerMax, 35 + ((index * 11) % 55))
  if animState then
    power = min(powerMax, max(0, floor((tonumber(animState.powerPct) or (power / powerMax)) * powerMax + 0.5)))
  end
  local powerBar = frame.targetPowerBar or frame.powerBar or frame.Power or frame.power
  if powerBar and (not powerBar.IsShown or powerBar:IsShown()) then
    SetBar(powerBar, power, powerMax, true, 0.10, 0.45, 0.95, 1)
  end

  ApplyPreviewText(frame, hp, hpMax, power, powerMax, class)
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
  SetShown(frame.statusAFKTimerText, false)
  if GF.HideSpellIndicators then GF.HideSpellIndicators(frame) end
  if GF.HideFrameAuras then GF.HideFrameAuras(frame) end
end

local function DeactivatePreviewFrame(frame)
  if not frame then return end
  ClearPreviewData(frame)
  if frame.Hide then frame:Hide() end

  -- Preview regions stay pooled on the button, but a hidden preview must not
  -- stay attached to unit-frame routing, events, group iteration, or ClickCast.
  if type(GF.UntrackFrame) == "function" then
    GF.UntrackFrame(frame)
  else
    if type(GF.UnregisterClickCastFrame) == "function" then
      GF.UnregisterClickCastFrame(frame)
    end
    local UF = MSUF and MSUF.UF
    if UF and type(UF.DetachFrame) == "function" then
      UF.DetachFrame(frame)
    elseif frame.UnregisterAllEvents then
      frame:UnregisterAllEvents()
    end
  end

  frame._msufGFPreviewDetached = true
  frame._msufGFPreviewApplyKey = nil
end

local function ReleasePreviewFrame(frames, index)
  local frame = frames and frames[index]
  if not frame then return false end
  frames[index] = nil
  DeactivatePreviewFrame(frame)

  frame._msufGFPreviewPooled = true
  frame._msufGFPreviewOwnerKind = nil
  frame._msufGFPreviewIndex = nil
  frame._msufGFPreviewClass = nil
  frame._msufGFPreviewRole = nil
  frame._msufGFPreviewAnimState = nil
  frame._msufGFKind = nil
  frame._msufGFEM2Kind = nil
  frame.configKey = nil
  frame.msufConfigKey = nil
  frame.MSUFSpec = nil
  frame.MSUFUnitKey = nil
  frame.unitKey = nil
  if frame.SetAttribute then frame:SetAttribute("unit", nil) end
  if frame.ClearAllPoints then frame:ClearAllPoints() end

  local free = GF._previewFreeFrames
  free[#free + 1] = frame
  return true
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
  local conf = layout and layout._msufGFKind and GF.GetConf and GF.GetConf(layout._msufGFKind)
  if not primary then
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
  local groupGrowth = conf and conf.groupGrowth
  if growth == "UP" then
    local left = groupGrowth ~= "LEFT"
    local anchor = left and "BOTTOMLEFT" or "BOTTOMRIGHT"
    local x = groupIndex * (blockW + spacing) + minor * (w + spacing)
    frame:SetPoint(anchor, layout, anchor, left and x or -x, major * (h + spacing))
  elseif growth == "RIGHT" then
    local down = groupGrowth ~= "UP"
    local anchor = down and "TOPLEFT" or "BOTTOMLEFT"
    local y = groupIndex * (blockH + spacing) + minor * (h + spacing)
    frame:SetPoint(anchor, layout, anchor, major * (w + spacing), down and -y or y)
  elseif growth == "LEFT" then
    local down = groupGrowth ~= "UP"
    local anchor = down and "TOPRIGHT" or "BOTTOMRIGHT"
    local y = groupIndex * (blockH + spacing) + minor * (h + spacing)
    frame:SetPoint(anchor, layout, anchor, -major * (w + spacing), down and -y or y)
  else
    local left = groupGrowth ~= "LEFT"
    local anchor = left and "TOPLEFT" or "TOPRIGHT"
    local x = groupIndex * (blockW + spacing) + minor * (w + spacing)
    frame:SetPoint(anchor, layout, anchor, left and x or -x, -major * (h + spacing))
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
  local unit = (frame.GetAttribute and frame:GetAttribute("unit")) or frame.MSUFUnitKey or "player"
  return tostring(kind) .. "\030" .. tostring(unit) .. "\030" .. tostring(revision or PreviewApplyRevision(kind))
    .. "\030" .. tostring(w) .. "\030" .. tostring(h)
end

local function ApplyPreviewSpecIfNeeded(frame, kind, reason, w, h, dirtyMask, expectedRevision)
  if not frame then return false end
  local currentRevision = PreviewApplyRevision(kind)
  local key = PreviewApplyKey(frame, kind, w, h, currentRevision)
  if dirtyMask == nil and frame._msufGFPreviewDetached ~= true
    and frame._msufGFPreviewApplyKey == key and frame.MSUFSpec then
    return true
  end
  local revisionCurrent = expectedRevision == nil or currentRevision == expectedRevision
  local canApplyDirty = frame._msufGFPreviewDetached ~= true
    and frame.MSUFSpec ~= nil
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
  if ok then
    frame._msufGFPreviewDetached = nil
    frame._msufGFPreviewApplyKey = PreviewApplyKey(frame, kind, w, h)
  end
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

local function AcquirePreviewFrame(parent)
  local free = GF._previewFreeFrames
  local freeCount = #free
  local frame = free[freeCount]
  if frame then
    free[freeCount] = nil
  else
    GF._previewFrameSerial = GF._previewFrameSerial + 1
    frame = CreateFrame("Button", "MSUF_GFPreviewButton_" .. GF._previewFrameSerial, parent, "BackdropTemplate")
    if frame.EnableMouse then frame:EnableMouse(false) end
  end

  frame._msufGFPreviewPooled = nil
  frame._msufGFPreviewDetached = true
  frame._msufGFPreviewApplyKey = nil
  frame._msufGFPreviewPositionKey = nil
  if frame:GetParent() ~= parent then frame:SetParent(parent) end
  return frame
end

local function EnsurePreviewFrame(kind, index, parent)
  local frames = GF._previewFrames[kind]
  if not frames then
    frames = {}
    GF._previewFrames[kind] = frames
  end
  local frame = frames[index]
  if not frame then
    frame = AcquirePreviewFrame(parent)
    frames[index] = frame
  elseif frame:GetParent() ~= parent then
    frame:SetParent(parent)
  end

  frame._msufGFIsPreviewFrame = true
  frame._msufGFPreviewOwnerKind = kind
  frame._msufGFPreviewIndex = index
  frame._msufGFKind = kind
  frame._msufGFEM2Kind = kind
  frame._msufIsGroupFrame = true
  frame.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ("gf_" .. kind)
  frame.configKey = "gf_" .. kind
  frame.MSUFUnitKey = "player"
  frame.unitKey = "player"
  if frame.SetAttribute then frame:SetAttribute("unit", "player") end
  return frame
end

local function PreparePreviewFrame(kind, index, layout, w, h, spacing, growth, upc, primary, blockW, blockH)
  local frame = EnsurePreviewFrame(kind, index, layout)
  SetPreviewFrameSize(frame, w, h)
  frame.MSUFUnitKey = "player"
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
  -- Menu dispel-overlay preview: only row 1 owns a native aura container, so
  -- the MSUF-drawn preview has to be re-stamped per row on every rebuild.
  -- One boolean read when no preview is active.
  if _G.MSUF_DispelOverlayPreviewMode == true
    and type(_G.MSUF_ApplyDispelOverlayPreviewToFrame) == "function" then
    _G.MSUF_ApplyDispelOverlayPreviewToFrame(frame)
  end
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
    if InCombat() then return end
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
  for i = #frames, visibleCount + 1, -1 do
    ReleasePreviewFrame(frames, i)
  end
  container:Show()
  local reason = opts and opts.reason or "MSUF_GF_PREVIEW"
  local dirtyMask = opts and opts.dirtyMask or nil
  local expectedRevision = PreviewApplyRevision(kind)
  if dirtyMask == nil and PreviewSpecsCurrent(frames, visibleCount, kind, w, h, expectedRevision) then
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
  local frames = GF._previewFrames[kind]
  if GF._previewActive[kind] ~= true
    and (not (container and container.IsShown and container:IsShown()))
    and not (frames and #frames > 0) then
    return true
  end
  BumpPreviewBuildSerial(kind)
  GF._previewActive[kind] = nil
  GF._previewShownCounts[kind] = nil
  if frames then
    for i = #frames, 1, -1 do
      ReleasePreviewFrame(frames, i)
    end
  end
  if container then container:Hide() end
  --- Hand the block border back to the live anchor: it was force-hidden for as
  --- long as this preview owned the block.
  if type(GF.ApplyGroupBorder) == "function" then GF.ApplyGroupBorder(kind) end
  return true
end

--- Combat is a hard ownership boundary for the visual-only preview pool.  The
--- options/edit-mode owner may still be logically open when combat starts, so
--- orphan detection alone is insufficient: detach every preview immediately.
function GF.HidePreviewsForCombat()
  local hidden = false
  for i = 1, #PREVIEW_KINDS do
    local kind = PREVIEW_KINDS[i]
    local frames = GF._previewFrames[kind]
    if GF._previewActive[kind] == true or (frames and #frames > 0) then
      hidden = GF.HidePreview(kind) or hidden
    end
  end
  return hidden
end

function GF.RefreshPreviewLayout(kind, opts)
  if InCombat() then return false end
  if kind == nil then
    local any = false
    for i = 1, #PREVIEW_KINDS do
      local activeKind = PREVIEW_KINDS[i]
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
    immediate = opts and opts.immediate == true or nil,
  })
end

GF.RefreshPreviewBox = GF.RefreshPreviewLayout

function GF.RefreshPreviewAnimation()
  if InCombat() then return false end
  local any = false
  for i = 1, #PREVIEW_KINDS do
    local kind = PREVIEW_KINDS[i]
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
  for i = 1, #PREVIEW_KINDS do
    local kind = PREVIEW_KINDS[i]
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
ExportPublic("MSUF_GF_RefreshPreviewAuras", function(kind) return GF.RefreshPreviewAuras(kind) end)
ExportPublic("MSUF_GF_RefreshPreviewSpellIndicators", function(kind) return GF.RefreshPreviewSpellIndicators(kind) end)
ExportPublic("MSUF_GF_RefreshPreviewAnimation", function() return GF.RefreshPreviewAnimation() end)
