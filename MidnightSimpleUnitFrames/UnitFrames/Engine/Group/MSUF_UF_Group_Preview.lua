--- UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua
--- Non-combat preview frames for group-frame menu/edit workflows.
---
--- Preview frames reuse the same compiled specs and visual elements as live
--- group frames, but they use fake roster data and never join secure headers.
--- Runtime hides live headers while previews are active so both do not overlap.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "GroupFrames")
local ExportPublic = MSUF.ExportPublic
local Auras = MSUF.Require("MSUF_Auras3", "GroupFrames/Preview")
local AuraPainter = assert(Auras.MockAuraPainter)
local PlacePreviewText = AuraPainter.PlaceText
local GroupDurationBar, TopSwipe = AuraPainter.GroupDurationBar, AuraPainter.TopSwipe

local GF = MSUF.GF or {}
MSUF.GF = GF

local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetNumGroupMembers = GetNumGroupMembers
local UnitName = UnitName
local issecretvalue = _G.issecretvalue
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

--- Preview scenes. A scene is one pool of preview frames for one group kind: its frames, free list, container
--- and layout frames, build serial and layer filter. The three default scenes (one per kind) are the on-screen
--- and Edit Mode previews; their tables are the GF._preview* tables the Edit Mode, header, aura and menu code
--- read. A scene made with GF.NewPreviewScene is isolated: it owns every table, and its frames are plain
--- Buttons painted through the spec pipeline that never reach the live registry, the unit index, click casting,
--- events, event scripts or secure attributes (_msufPreviewScope in the unit-frame core).
local Scene = {}
Scene.__index = Scene
local defaultScenes = {}
local isolatedScenes = setmetatable({}, { __mode = "k" })
local isolatedSceneCount = 0

for i = 1, #PREVIEW_KINDS do
  local kind = PREVIEW_KINDS[i]
  defaultScenes[kind] = setmetatable({ kind = kind, default = true, free = GF._previewFreeFrames, t = {
    frames = GF._previewFrames, active = GF._previewActive, count = GF._previewShownCounts,
    anchor = GF._previewAnchorFrame, container = GF._previewContainer, layout = GF._previewLayoutFrame,
    serial = GF._previewBuildSerial,
  } }, Scene)
end

local function NewScene(kind)
  local scene = setmetatable({ kind = kind, free = {}, t = {
    frames = {}, active = {}, count = {}, anchor = {}, container = {}, layout = {}, serial = {},
  } }, Scene)
  isolatedScenes[scene] = true
  isolatedSceneCount = isolatedSceneCount + 1
  return scene
end

local function BumpSceneSerial(scene)
  local serial, kind = scene.t.serial, scene.kind
  serial[kind] = (serial[kind] or 0) + 1
  return serial[kind]
end

local function CurrentSceneSerial(scene)
  return scene.t.serial[scene.kind] or 0
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

local VALID_POINTS = {
  CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
  TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

--- The menu's LAYERS rail is the one place a user switches preview elements on
--- and off, so the in-world dummies read the same switches as the docked
--- preview instead of answering a different question about the same profile.
--- Both nil means no menu has spoken yet: everything the settings enable draws.
--- Solo (Shift-click) is exclusive here rather than the menu's 0.15 dimming --
--- these are live frames whose region alpha belongs to the Alpha element.
local previewLayerVisible, previewLayerSolo
--- The two names above are the filter the running paint reads: the default scenes' (the menu pushes it through
--- GF.SetPreviewLayerFilter). An isolated scene swaps its own in for the length of one call and puts the
--- previous pair back, so the default scenes' paint costs nothing extra.
local savedLayerVisible, savedLayerSolo
--- The isolated scene whose call is running (nil for the default scenes, which paint live-adjacent dummies) and
--- the clock its root was handed (nil unless the owner animates it). An isolated scene paints static sample data,
--- or follows its owner's clock: no unit query and no shared animation clock.
local activeScene, sceneElapsed

local function EnterScene(scene)
  if scene.default then return end
  savedLayerVisible, savedLayerSolo = previewLayerVisible, previewLayerSolo
  previewLayerVisible, previewLayerSolo = scene.layerVisible, scene.layerSolo
  activeScene = scene
  local root = scene.root
  sceneElapsed = root and root.animating and root.elapsed or nil
end

local function LeaveScene(scene)
  if scene.default then return end
  previewLayerVisible, previewLayerSolo = savedLayerVisible, savedLayerSolo
  activeScene, sceneElapsed = nil, nil
end

--- Guides and Bounds are drag-handle chrome that exists only inside the docked
--- preview. Soloing one of those must not blank the in-world dummies, so a solo
--- on a key the dummies do not own is dropped rather than applied.
local PREVIEW_LAYER_KEYS = {
  text = true, power = true, status = true, si = true, auraText = true,
  buff = true, trackedBuff = true, debuff = true, external = true,
}

local function PreviewLayerOn(key)
  if previewLayerSolo ~= nil then return previewLayerSolo == key end
  return not (previewLayerVisible and previewLayerVisible[key] == false)
end

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

--- Hard dependencies on exports of files that load before this one (the UF
--- factory, config and preview animation, the Auras3 preview). Resolved per call
--- on the cold preview paths, so a fixture that never reaches one need not stub it.
local function Dep(name)
  return MSUF.Require(name, "UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
end

--- The role a preview row stands for, by position (tank, healer, damage, damage, healer, ...).
function GF.PreviewSampleRole(frame)
  local scene = frame and frame._msufPreviewScene
  return scene and scene.role or PREVIEW_ROLES[(((frame and frame._msufGFPreviewIndex) or 1) - 1) % #PREVIEW_ROLES + 1]
end

local function PreviewAnimationActive()
  -- The animation module's own flag; the exported accessor (and its missing-dependency error) only without the module.
  local animation = MSUF.PreviewAnimation
  if animation then return animation.IsEnabled() == true end
  return Dep("MSUF_IsPreviewAnimationEnabled")() == true
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

local AnchorPoint = GF.GetAnchorPoint

--- Both sides of a group anchor come from the single visible Anchor Point; see
--- GF.ResolveAnchorPoint (MSUF_GroupFrames_DB.lua) for the legacy pair it retires.
local function ResolveAnchorPoint(kind, conf, parent)
  if GF.ResolveAnchorPoint then return GF.ResolveAnchorPoint(kind, conf, parent) end
  local point = AnchorPoint(conf)
  return point, point
end




local ClampPreviewOffsetOnScreen = _G.MSUF_UF_ClampAnchorOffsetOnScreen

local function ResolveAnchorFrame(conf, owner)
  if type(GF.ResolveAnchorFrame) == "function" then
    local frame, missing = GF.ResolveAnchorFrame(conf, owner)
    if missing then Dep("MSUF_ScheduleLateAnchorReanchor")() end
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

local function ActivePreviewCount(scene)
  local kind, t = scene.kind, scene.t
  if t.active[kind] ~= true then return nil end
  local n = tonumber(t.count[kind])
  if n and n > 0 then return floor(n + 0.5) end
  return DefaultPreviewCount(kind)
end

--- The count a preview frame lays out for: the one its own scene shows, else its kind's default scene.
function GF.GetActivePreviewCount(kind, frame)
  local scene = frame and frame._msufPreviewScene
  if scene then return ActivePreviewCount(scene) end
  if GF._previewActive[kind] ~= true then return nil end
  local n = tonumber(GF._previewShownCounts[kind])
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

local function GetPositionCount(scene)
  local kind = scene.kind
  local previewCount = ActivePreviewCount(scene)
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

function Scene:SetParent(parent)
  local t, kind = self.t, self.kind
  if t.anchor[kind] == parent then return true end
  t.anchor[kind] = parent
  BumpSceneSerial(self)
  local container = t.container[kind]
  local layout = t.layout[kind]
  if container then container._msufGFPreviewPositionKey = nil end
  if layout then layout._msufGFPreviewPositionKey = nil end
  return true
end

function GF.SetPreviewAnchor(kind, parent)
  kind = NormalizeKind(kind)
  if not kind then return false end
  return (defaultScenes[kind]):SetParent(parent)
end

local PreviewsAllowed

local function EnsureContainer(scene, parent)
  local desiredParent = parent or UIParent
  local kind, t, named = scene.kind, scene.t, scene.default
  local container = t.container[kind]
  if not container then
    container = PixelLayoutRegion(CreateFrame("Frame", named and ("MSUF_GFPreviewContainer_" .. kind) or nil, desiredParent))
    container:EnableMouse(false)
    t.container[kind] = container
  end
  if container:GetParent() ~= desiredParent then container:SetParent(desiredParent) end

  local layout = t.layout[kind]
  if not layout then
    layout = PixelLayoutRegion(CreateFrame("Frame", named and ("MSUF_GFPreviewLayout_" .. kind) or nil, container))
    layout:EnableMouse(false)
    t.layout[kind] = layout
  end
  if layout:GetParent() ~= container then layout:SetParent(container) end
  return container, layout
end

--- Position the preview container using the same grid math as live headers so
--- menu edits match the real layout as closely as possible.
local function PositionContainer(scene, count)
  local kind, isolated = scene.kind, not scene.default
  local conf = GF.GetConf and GF.GetConf(kind) or {}
  -- A layout that keeps the raid groups apart sizes itself by the groups the live roster fills unless it is told how
  -- many there are; a scene reads no roster, so it lays out the configured number.
  local groups
  if isolated then
    groups = floor((tonumber(conf.maxColumns) or 8) + 0.5)
    if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
  end
  local posCount = GetPositionCount(scene) or DefaultPreviewCount(kind)
  -- The saved grid position is the on-screen preview's; an isolated scene never reads or migrates it.
  if GF.EnsureStableGridPosition and not isolated then
    GF.EnsureStableGridPosition(kind, posCount, conf)
  end
  local _, _, posW, posH = GF.GetGridMetrics(kind, posCount, groups)
  local _, _, _, _, w, h, spacing, growth, upc, _, _, _, primary, _, _, blockW, blockH = GF.GetGridMetrics(kind, count, groups)
  local parent = scene.t.anchor[kind]
  if isolated then parent = parent or UIParent end
  local container, layout = EnsureContainer(scene, parent or UIParent)

  local containerW, containerH = max(posW or w or 1, 1), max(posH or h or 1, 1)
  -- An owner that shows one frame asks the container to hug it: the grid footprint of a layout that keeps the raid
  -- groups apart is a whole group column, and the lone frame sits at its corner, away from the owner's centre.
  if isolated and scene.fit == true then containerW, containerH = max(w or 1, 1), max(h or 1, 1) end
  local point, relativePoint, relative, x, y
  if parent then
    point, relativePoint, relative, x, y = "CENTER", "CENTER", parent, 0, 0
  else
    relative = ResolveAnchorFrame(conf, container)
    -- Resolving can retire a legacy relativePoint into the offsets, so read
    -- those afterwards.
    point, relativePoint = ResolveAnchorPoint(kind, conf, relative)
    -- Tier positions and the solo centring resolve for the shown sample count.
    local xKey, yKey, centered = "offsetX", "offsetY", false
    if GF.ResolveGroupPositionKeys then xKey, yKey, centered = GF.ResolveGroupPositionKeys(kind, conf, count) end
    if centered then
      relative, point, relativePoint, x, y = UIParent, "CENTER", "CENTER", 0, 0
    else
      local cx, cy = tonumber(conf[xKey]), tonumber(conf[yKey])
      if cx == nil or cy == nil then cx, cy = tonumber(conf.offsetX), tonumber(conf.offsetY) end
      if cx == nil or cy == nil then cx, cy = DefaultCenter(kind) end
      x, y = floor(cx + 0.5), floor(cy + 0.5)
    end
  end
  if isolated then
    -- The owner's frame places and scales the scene; nothing clamps it to the screen.
  elseif GF.ConfigureAnchorPointScreenClamp then
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
  -- An isolated scene is zoomed as a whole: the owner picks the scale, the frames keep their spec size.
  if isolated and container._msufGFPreviewScale ~= (scene.scale or 1) then
    container._msufGFPreviewScale = scene.scale or 1
    container:SetScale(scene.scale or 1)
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
  size = tonumber(size) or 10
  if not (size >= 6) then size = 6 end
  if fontString._msufGFPreviewFontSize == size then return end
  fontString._msufGFPreviewFontSize = size
  fontString:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
end


local function EnsureAuraPreview(frame, index, poolKey)
  local pool = frame[poolKey]
  if not pool then
    pool = {}
    frame[poolKey] = pool
  end
  local visual = pool[index]
  if visual then return visual end

  visual = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
  visual:EnableMouse(false)
  if visual.SetMouseMotionEnabled then visual:SetMouseMotionEnabled(false) end
  visual._texture = PixelLayoutRegion(visual:CreateTexture(nil, "ARTWORK"))
  visual._texture:SetAllPoints(visual)
  pool[index] = visual
  return visual
end

local function EnsurePreviewTexture(visual, key, layer, sublevel)
  local texture = visual[key]
  if not texture then
    texture = PixelLayoutRegion(visual:CreateTexture(nil, layer, nil, sublevel))
    visual[key] = texture
  end
  return texture
end

local function EnsurePreviewFontString(visual, key)
  local fontString = visual[key]
  if not fontString then
    fontString = PixelLayoutRegion(visual:CreateFontString(nil, "OVERLAY"))
    visual[key] = fontString
  end
  return fontString
end

local function ShowPreviewTimer(visual, cfg, text)
  local timer = EnsurePreviewFontString(visual, "_timer")
  SetPreviewFont(timer, cfg.cooldownSize or 8)
  timer:SetText(text)
  timer:SetTextColor(1, 1, 1, 1)
  PlacePreviewText(timer, visual, cfg.cooldownAnchor or "CENTER", cfg.cooldownX or 0, cfg.cooldownY or 0, "POINT_ONLY")
  timer:Show()
end

--- Swipe, timer, stack and duration bar of an icon-type lane aura or indicator;
--- both read the same field names. Returns the icon's swipe region, if any.
local function PaintIconLayers(visual, cfg, size, barOnly, textOn, timerText)
  if cfg.showCooldownSwipe == true and not barOnly then
    TopSwipe(EnsurePreviewTexture(visual, "_swipe", "OVERLAY", 1), visual, size, 0.42)
  end
  if cfg.showCooldownText == true and textOn then ShowPreviewTimer(visual, cfg, timerText) end
  if cfg.showStacks == true and textOn then
    local stack = EnsurePreviewFontString(visual, "_stack")
    SetPreviewFont(stack, cfg.stackSize or 10)
    stack:SetText("2")
    local r, g, b
    if type(Auras.GetStackCountColor) == "function" then r, g, b = Auras.GetStackCountColor() end
    stack:SetTextColor(r or 1, g or 1, b or 1, 1)
    PlacePreviewText(stack, visual, cfg.stackAnchor or "BOTTOMRIGHT", cfg.stackX or 0, cfg.stackY or 0, "POINT_ONLY")
    stack:Show()
  end
  if cfg.showDurationBar == true then
    local height = tonumber(cfg.durationBarHeight) or 2
    if not (height < size) then height = size elseif height < 1 then height = 1 end
    GroupDurationBar(EnsurePreviewTexture(visual, "_durationBar", "OVERLAY", 2), visual, cfg.durationBarPosition, height)
  end
  return visual._swipe
end



local function EnsureFrameAuraLaneHost(frame, key)
  local hosts = frame._msufGFFrameAuraPreviewHosts
  if not hosts then
    hosts = {}
    frame._msufGFFrameAuraPreviewHosts = hosts
  end
  local host = hosts[key]
  if host then return host end
  host = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
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
  local perRow = floor((tonumber(lane.perRow) or 1) + 0.5)
  if not (perRow >= 1) then perRow = 1 end
  local column = slot % perRow
  local row = floor(slot / perRow)
  local x = column * step * (tonumber(lane.xSign) or 1)
  local y = row * step * (tonumber(lane.ySign) or -1)
  return x, y
end

local function ApplyFrameAuraPreview(frame, kind, visual, lane, descriptor, slot, sampleIndex, host)
  local A3 = Auras
  local size = tonumber(lane.size) or 18
  if not (size >= 1) then size = 1 end
  local initialAnchor = lane.initialAnchor
  if not VALID_POINTS[initialAnchor] then
    initialAnchor = tostring(initialAnchor or "TOPLEFT"):upper()
    if not VALID_POINTS[initialAnchor] then initialAnchor = "TOPLEFT" end
  end
  local x, y = FrameAuraPreviewOffset(lane, slot)

  visual:ClearAllPoints()
  visual:SetSize(size, size)
  visual:SetPoint(initialAnchor, host, initialAnchor, x, y)
  if visual.SetFrameLevel and host.GetFrameLevel then visual:SetFrameLevel((host:GetFrameLevel() or 0) + 1) end
  if visual.SetAlpha then visual:SetAlpha(1) end

  local texture = visual._texture
  local textures = descriptor.textures
  texture:SetTexture(textures[((sampleIndex - 1) % #textures) + 1] or PREVIEW_QUESTION)
  local zoom = tonumber(lane.iconZoom) or 100
  if not (zoom < 200) then zoom = 200 elseif zoom < 100 then zoom = 100 end
  local inset = A3.IconShape.IconZoomInset(zoom)
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

  swipe = PaintIconLayers(visual, lane, size, barOnly, PreviewLayerOn("auraText"), sampleIndex == 1 and "12" or "8")

  if type(A3.ApplyAuraIconShape) == "function" then
    A3.ApplyAuraIconShape(visual, lane.iconShape, nil, texture, swipe)
  end
  if type(A3.ApplyIconStylePreview) == "function" then
    local selectedValue2
    if not (barOnly) then selectedValue2 = lane.iconStyle end
    A3.ApplyIconStylePreview(visual, selectedValue2, size, lane.iconShape)
  end
  if lane.showAuraBorder == true and not barOnly then
    dispelBorder = EnsurePreviewTexture(visual, "_dispelBorder", "OVERLAY", 5)
    if type(A3.ApplyAuraDispelPreview) == "function"
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

--- Each preview row carries its own PatchFrameSpec copy of one compiled base
--- spec, so resolving the aura config against the row missed the runtime's
--- per-spec shared cache and recompiled every lane and slot once per row (a
--- 20-row raid build: 20 configs, 80 lane compiles). The lanes and slots the
--- painters below read reach the spec only through these shared references.
--- While the row still mirrors its base, resolve against the base, the path
--- RefreshPreviewAuras and RefreshPreviewSpellIndicators already take. Classic
--- flavors compile group lanes from the whole spec and share no cache, so they
--- keep resolving per row.
local SHARE_PREVIEW_AURA_CONFIG = not (MSUF.Client and MSUF.Client.IsClassic)
local function PreviewAuraConfigSpec(frame, compiledSpec)
  if compiledSpec ~= nil or not SHARE_PREVIEW_AURA_CONFIG then return compiledSpec end
  local spec = frame and frame.MSUFSpec
  local base = frame and frame._msufGFSpecBase
  if not (spec and base) or base == spec or base.auras ~= spec.auras
    or base.spellIndicators ~= spec.spellIndicators or base.cornerIndicators ~= spec.cornerIndicators
    or base.portrait ~= spec.portrait or base.dispelSymbol ~= spec.dispelSymbol then
    return nil
  end
  return base
end

--- Lay out and paint the stand-ins of the lanes `descriptors` names that `lanes` enables; true when any icon shows.
local function PaintFrameAuraLanes(frame, kind, lanes, descriptors, previewIndex)
  local used = 0
  previewIndex = max(1, floor((tonumber(previewIndex) or 1) + 0.5))
  for laneIndex = 1, #descriptors do
    local descriptor = descriptors[laneIndex]
    local lane = lanes[descriptor.key]
    local maxCount = max(0, floor((tonumber(lane and lane.max) or 0) + 0.5))
    local host = EnsureFrameAuraLaneHost(frame, descriptor.key)
    if lane and lane.enabled == true and maxCount > 0 and PreviewLayerOn(descriptor.key) then
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
        ApplyFrameAuraPreview(frame, kind, EnsureAuraPreview(frame, used, "_msufGFFrameAuraPreviews"),
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
    and A3.ResolveAuraPreviewConfig(frame, frame.MSUFUnitKey or "player", PreviewAuraConfigSpec(frame, compiledSpec)) or nil
  local lanes = runtimeConfig and runtimeConfig.lanes
  if not lanes then
    GF.HideFrameAuras(frame)
    return false
  end
  return PaintFrameAuraLanes(frame, kind, lanes, PREVIEW_AURA_LANES, previewIndex)
end

local PREVIEW_UNIT_AURA_LANES = { PREVIEW_AURA_LANES[1], PREVIEW_AURA_LANES[3] }

--- Aura stand-ins of a unit scene frame: the buff and debuff lanes of the unit's compiled aura configuration, painted
--- like a group frame's. The layer filter of the on-screen previews is lifted for the call.
function GF.PreviewUnitFrameAuras(frame, unit, spec, previewIndex)
  if InCombat() then return false end
  local auras = spec and spec.auras
  local A3 = MSUF and MSUF.MSUF_Auras3
  local config = auras and auras.enabled == true and A3 and A3.ResolveAuraPreviewConfig(frame, unit, spec)
  local lanes = config and config.lanes
  if not lanes then
    GF.HideFrameAuras(frame)
    return false
  end
  local heldVisible, heldSolo = previewLayerVisible, previewLayerSolo
  previewLayerVisible, previewLayerSolo = nil, nil
  local shown = PaintFrameAuraLanes(frame, "unit", lanes, PREVIEW_UNIT_AURA_LANES, previewIndex)
  previewLayerVisible, previewLayerSolo = heldVisible, heldSolo
  return shown
end

--- Refresh only the pooled Aura stand-ins on active Edit Mode group dummies.
--- Menu sliders use this path while dragging so raw DB geometry reaches the
--- dummy frames immediately without reapplying live frames or rebuilding the
--- rest of each preview button. No preview survives combat, and the hard guard
--- keeps this entry point inert even if an external caller races combat entry.
local function RefreshSceneAuras(scene)
  local kind, t = scene.kind, scene.t
  if type(GF.InvalidateCompiledSpecs) == "function" then GF.InvalidateCompiledSpecs(kind) end
  if not t.active[kind] then return false end
  local compile = GF.GetCompiledSpec or GF.CompileSpec
  local spec = type(compile) == "function" and compile(kind) or nil
  local auras = spec and spec.auras
  local frames = t.frames[kind]
  if not (auras and frames) then return false end

  local refreshed = false
  for i = 1, #frames do
    local frame = frames[i]
    if frame and frame.IsShown and frame:IsShown() then
      GF.PreviewFrameAuras(frame, kind, frame._msufGFPreviewIndex or i, auras, spec)
      refreshed = true
    end
  end
  return refreshed
end

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
  return RefreshSceneAuras(defaultScenes[kind])
end

local function HideSpellFrameEffectPreview(visual)
  local owner = visual and visual._frameEffectOwner
  if not owner then return false end
  local runtime = MSUF and MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.SpellIndicators
  if runtime and type(runtime.HidePreviewFrameEffect) == "function" then
    return runtime.HidePreviewFrameEffect(owner) == true
  end
  owner:Hide()
  return true
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
  HideSpellFrameEffectPreview(visual)
  local A3 = MSUF and MSUF.MSUF_Auras3
  if A3 and type(A3.ApplyIconStylePreview) == "function" then
    A3.ApplyIconStylePreview(visual, nil)
  end
end

--- Full-Frame effect surfaces for the Group preview.  The owner is a child of
--- the preview frame rather than of the icon host, because an effect-only slot
--- (Display as: none) hides that host while the effect must stay visible.
local function EnsureSpellFrameEffectOwner(visual, frame)
  local owner = visual._frameEffectOwner
  if not owner then
    owner = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
    owner:EnableMouse(false)
    if owner.SetMouseMotionEnabled then owner:SetMouseMotionEnabled(false) end
    visual._frameEffectOwner = owner
  elseif owner:GetParent() ~= frame then
    owner:SetParent(frame)
  end
  owner:ClearAllPoints()
  owner:SetAllPoints(frame)
  return owner
end

--- Previews paint through the live renderer, exactly like the UnitFrame preview
--- does.  A second preview-only implementation had already drifted -- it drew
--- Glow as four edges instead of the runtime's radial halo and used its own
--- Pulse alpha and blend modes -- and only one of the two could ever match the
--- frames.  Layer, priority, thickness and colors now come from the single
--- owner, so preview and runtime cannot disagree again.
local function ApplySpellFrameEffectPreview(visual, frame, slot)
  local runtime = MSUF and MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.SpellIndicators
  local effect = slot and slot.frameEffect
  local health = frame and (frame.hpBar or frame.Health or frame.health)
  if not (visual and frame and health and type(effect) == "table"
    and runtime and type(runtime.ApplyPreviewFrameEffect) == "function") then
    HideSpellFrameEffectPreview(visual)
    return false
  end
  return runtime.ApplyPreviewFrameEffect(EnsureSpellFrameEffectOwner(visual, frame),
    effect, frame) == true
end

local function ApplySpellIndicatorPreview(frame, kind, visual, slot)
  local visualType = slot and tostring(slot.visual or "none"):lower() or "none"
  local hiddenVisual = slot and slot.hiddenVisual == true
  local effectShown = ApplySpellFrameEffectPreview(visual, frame, slot)
  if not slot or (visualType == "none" and not effectShown) then
    HideSpellIndicatorPreview(visual)
    return false
  end

  local size = tonumber(slot.size) or 18
  if not (size >= 1) then size = 1 end
  local width = tonumber(slot.width) or size
  if not (width >= 1) then width = 1 end
  local height = tonumber(slot.height) or size
  if not (height >= 1) then height = 1 end
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
    if slot.showCooldownText == true then ShowPreviewTimer(visual, slot, "12") end
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
    PlacePreviewText(stack, visual, "CENTER", 0, 0, "POINT_ONLY")
    stack:Show()
  else
    texture:SetTexture(slot.icon or PREVIEW_QUESTION)
    local zoom = tonumber(slot.iconZoom) or 100
    if not (zoom < 200) then zoom = 200 elseif zoom < 100 then zoom = 100 end
    local inset = A3.IconShape.IconZoomInset(zoom)
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetShown(not barOnly)

    PaintIconLayers(visual, slot, size, barOnly, true, "12")

    if A3 and type(A3.ApplyIconStylePreview) == "function" then
      local selectedValue1
      if not (barOnly) then selectedValue1 = slot.iconStyle end
      A3.ApplyIconStylePreview(visual, selectedValue1, size)
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
    and A3.ResolveAuraPreviewConfig(frame, frame and (frame.MSUFUnitKey or "player"), PreviewAuraConfigSpec(frame, compiledSpec)) or nil
  local root = runtimeConfig and runtimeConfig.spellIndicators
  local slots = root and root.slots
  if not (root and root.enabled == true and type(slots) == "table") or not PreviewLayerOn("si") then
    GF.HideSpellIndicators(frame)
    return false
  end

  local used = 0
  for i = 1, #slots do
    local slot = slots[i]
    if slot and slot.enabled == true then
      used = used + 1
      ApplySpellIndicatorPreview(frame, kind, EnsureAuraPreview(frame, used, "_msufGFSpellIndicatorPreviews"), slot)
    end
  end
  local pool = frame._msufGFSpellIndicatorPreviews
  for i = used + 1, pool and #pool or 0 do HideSpellIndicatorPreview(pool[i]) end
  return used > 0
end

--- Refresh only pooled Spell Indicator stand-ins on active Edit Mode dummies.
--- This is a configuration/preview cold path: no aura queries, subscriptions,
--- timers, or idle scripts are installed, and combat exits before invalidation.
local function RefreshSceneSpellIndicators(scene)
  local kind, t = scene.kind, scene.t
  local spellIndicators = GF.SpellIndicators
  if spellIndicators and type(spellIndicators.InvalidateRuntimeCaches) == "function" then
    spellIndicators.InvalidateRuntimeCaches()
  end
  if type(GF.InvalidateCompiledSpecs) == "function" then GF.InvalidateCompiledSpecs(kind) end
  if not t.active[kind] then return false end
  local compile = GF.GetCompiledSpec or GF.CompileSpec
  local spec = type(compile) == "function" and compile(kind) or nil
  local frames = t.frames[kind]
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
  return RefreshSceneSpellIndicators(defaultScenes[kind])
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

local function SetBar(bar, value, maxValue, animate, r, g, b, a)
  if not bar then return end
  if bar.SetMinMaxValues then bar:SetMinMaxValues(0, maxValue or 100) end
  if bar.SetValue then bar:SetValue(value or 0, animate == true and bar._msufSmoothInterp or nil) end
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

local function PercentFactory(pct)
  pct = floor((pct or 0) + 0.5)
  return function() return pct end
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

local function ApplyPreviewText(frame, hp, hpMax, power, powerMax, class, absorb)
  local text = MSUF and MSUF.UFText
  local rt = frame and frame._msufTextRuntime
  if not (text and rt and text.UpdateTextSlots) then return end

  rt.healthMissing = max(0, (hpMax or 0) - (hp or 0))
  -- A scene sample carries the absorb amount its absorb text and combined health text show (the live frame asks
  -- the unit for it); nil clears the previous one.
  if activeScene then
    rt.healthAbsorb = absorb
  end
  text.UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.MSUFUnitKey or "player",
    PercentFactory((hp / max(hpMax, 1)) * 100), rt.healthNeedsPercent, rt)
  if activeScene and absorb ~= nil and (rt.healthAbsorbSlotCount or 0) > 0 then
    text.UpdateTextSlots(rt.healthAbsorbSlots, rt.healthAbsorbSlotCount, nil, nil, frame.MSUFUnitKey or "player", nil, false, rt)
  end
  if rt.healthColorByClass == true and text.SetHealthTextColor then
    local r, g, b = ClassColor(class)
    text.SetHealthTextColor(frame, rt, r, g, b, rt.healthTextAlpha or rt.textColorA or 1)
  elseif rt.healthColorByHealth == true and text.UpdateHealthTextColor then
    if activeScene and text.SetSampleHealthTextColor then
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
--- is the whole chip: hiding them all is exactly what ClearPreviewData does.
local function HidePreviewStatus(frame)
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
  SetShown(frame.combatStateIndicatorIcon, false)
  SetShown(frame.statusIndicatorText, false)
  SetShown(frame.statusAFKTimerText, false)
end

local function ApplyPreviewStatus(frame, kind, index, role)
  if not PreviewLayerOn("status") then
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
    local playerLevel = not activeScene and _G.UnitLevel and tonumber(_G.UnitLevel("player")) or nil
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
local function ApplyPreviewData(frame, slot, kind)
  if InCombat() then return false end
  if not frame then return false end
  if not frame.MSUFSpec then return false end
  kind = NormalizeKind(kind) or "party"
  -- The member this frame shows was chosen when the frame was prepared for its slot (PreviewMember).
  local index = frame._msufGFPreviewIndex or slot
  -- A scene can pin one sample (name, class, fractions) for all its rows; see Scene:SetSample.
  local sample = activeScene and activeScene.sample
  local class = sample and sample.class or PREVIEW_CLASSES[((index - 1) % #PREVIEW_CLASSES) + 1]
  local role = PREVIEW_ROLES[((index - 1) % #PREVIEW_ROLES) + 1]
  -- An isolated scene never asks the client who the player is: every index draws its sample name.
  local playerName = not activeScene and UnitName and UnitName("player")
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

  local textLayerOn = PreviewLayerOn("text")
  local showPreviewName = frame.nameText and frame.nameText:IsShown() and textLayerOn
  -- Keep the fake identity authoritative when ordinary unit events refresh the
  -- player-backed dummy outside Edit Mode.
  frame._msufPreviewNameText = (showPreviewName or activeScene) and (name or "Preview") or nil
  if showPreviewName then
    -- The engine paints the sample name: UTF-8 aware legacy shortening, or the
    -- full name inside the layout's clip window, exactly like a live frame.
    if activeScene then
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
  if activeScene then
    -- The scene's own clock, not the shared preview animation: scenes animate only while their owner hands one over.
    if sceneElapsed then
      animState = Dep("MSUF_BuildPreviewAnimationFrameState")(frame, index, kind, frame._msufGFPreviewAnimState or {}, sceneElapsed)
    end
  elseif PreviewAnimationActive() and _G.MSUF_GetPreviewAnimationFrameState then
    animState = _G.MSUF_GetPreviewAnimationFrameState(frame, index, kind, frame._msufGFPreviewAnimState or {})
  end
  if animState then
    frame._msufGFPreviewAnimState = animState
    hpPct = min(0.98, max(0.02, tonumber(animState.hpPct) or hpPct))
  end
  local hpMax = sample and sample.hpMax or 100
  local hp = floor(hpPct * hpMax + 0.5)
  SetBar(frame.hpBar or frame.Health or frame.health, hp, hpMax, true, PreviewHealthColor(frame, class, hpPct))

  local powerMax = sample and sample.powerMax or 100
  local power = sample and sample.powerPct and floor(sample.powerPct * powerMax + 0.5) or min(powerMax, 35 + ((index * 11) % 55))
  if animState then
    power = min(powerMax, max(0, floor((tonumber(animState.powerPct) or (power / powerMax)) * powerMax + 0.5)))
  end
  local powerBar = frame.targetPowerBar or frame.powerBar or frame.Power or frame.power
  -- The layer only hides the drawn bar; the health geometry keeps following the
  -- settings, so switching the chip never fakes a layout change on the dummies.
  if powerBar and (not powerBar.IsShown or powerBar:IsShown()) then
    if PreviewLayerOn("power") then
      local color = sample and sample.powerColor
      if color then
        SetBar(powerBar, power, powerMax, true, color[1], color[2], color[3], 1)
      else
        SetBar(powerBar, power, powerMax, true, 0.10, 0.45, 0.95, 1)
      end
    elseif powerBar.Hide then
      powerBar:Hide()
    end
  end

  if textLayerOn then
    ApplyPreviewText(frame, hp, hpMax, power, powerMax, class, sample and sample.absorb)
  else
    ClearPreviewTexts(frame)
  end
  -- A scene frame skips the spec apply's live updates, so the elements whose update paints a preview sample (and
  -- reads no unit for a preview frame) run here.
  if activeScene then
    if sample then
      ApplyScenePrediction(frame, sample, hpPct, animState)
      local tempMax = MSUF.UF.elements and MSUF.UF.elements.TempMaxHealth
      if tempMax and tempMax.ApplySample then tempMax.ApplySample(frame, sample.tempMaxPct) end
    end
    if activeScene.bodyOnly then
      -- The owner draws the portrait, icons, auras and indicators (its handles) over this body.
      SetShown(frame.MSUFPortraitHolder, false)
      frame:Show()
      return true
    end
    local portrait = MSUF.UF.elements and MSUF.UF.elements.Portrait
    if classPinned and portrait and portrait.SceneApply then portrait.SceneApply(frame, frame.MSUFSpec) end
    local threat = MSUF.UF.elements and MSUF.UF.elements.ThreatIndicator
    if threat and threat.Update then threat.Update(frame, "MSUF_PREVIEW") end
  end
  ApplyPreviewStatus(frame, kind, index, role)
  if animState and frame.combatStateIndicatorIcon and PreviewLayerOn("status") then
    if frame.combatStateIndicatorIcon.SetAlpha then frame.combatStateIndicatorIcon:SetAlpha(0.55 + ((animState.pulse or 0) * 0.45)) end
    frame.combatStateIndicatorIcon:Show()
  end
  if GF.PreviewSpellIndicators then GF.PreviewSpellIndicators(frame, kind, nil, nil) end
  if GF.PreviewFrameAuras then GF.PreviewFrameAuras(frame, kind, index) end
  frame:Show()
  return true
end

--- Menu -> engine bridge for the LAYERS rail. The menu owns the switches; this
--- only mirrors them onto the in-world dummies and re-seeds the frames already
--- on screen. Callers push on every preview refresh, so the signature compare
--- is what keeps that from re-seeding forty frames per mouse-over.
function GF.SetPreviewLayerFilter(visible, solo)
  if type(visible) ~= "table" then visible = nil end
  if type(solo) ~= "string" or PREVIEW_LAYER_KEYS[solo] ~= true then solo = nil end
  previewLayerVisible, previewLayerSolo = visible, solo
  -- Combat bails before the signature walk, not after it. Previews are already
  -- force-hidden for the fight, so there is nothing the comparison could decide
  -- -- and recording a signature we never acted on would let the first
  -- out-of-combat push match it and skip the re-seed the frames still need.
  if InCombat() then
    GF._previewLayerSignature = nil
    return false
  end
  local signature = tostring(solo or "-")
  if visible then
    -- Only the off switches carry information; a key that is on is the default.
    for key, value in pairs(visible) do
      if value == false then signature = signature .. "\030" .. tostring(key) end
    end
  end
  if GF._previewLayerSignature == signature then return false end
  GF._previewLayerSignature = signature

  local reseeded = false
  for i = 1, #PREVIEW_KINDS do
    local kind = PREVIEW_KINDS[i]
    if GF._previewActive[kind] == true then
      local frames = GF._previewFrames[kind]
      for index = 1, #(frames or {}) do
        local frame = frames[index]
        if frame and frame._msufGFPreviewActive then
          ApplyPreviewData(frame, index, kind)
          reseeded = true
        end
      end
    end
  end
  return reseeded
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
  SetShown(frame.roleIcon, false)
  SetShown(frame.raidIcon, false)
  SetShown(frame.leaderIcon, false)
  SetShown(frame.assistIcon, false)
  SetShown(frame.readyCheckIcon, false)
  SetShown(frame.resurrectIcon or frame.incomingResIndicatorIcon, false)
  SetShown(frame.pvpIcon or frame.pvpIndicatorIcon, false)
  SetShown(frame.phaseIcon, false)
  SetShown(frame.raidGroupNameText, false)
  SetShown(frame.levelText, false)
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

local function ReleasePreviewFrame(scene, frames, index)
  local frame = frames[index]
  if not frame then return false end
  frames[index] = nil
  DeactivatePreviewFrame(frame)

  frame._msufGFPreviewPooled = true
  frame._msufGFPreviewOwnerKind = nil
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
  if scene.default and frame.SetAttribute then frame:SetAttribute("unit", nil) end
  if frame.ClearAllPoints then frame:ClearAllPoints() end

  local free = scene.free
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
  if frame._msufPreviewScope == true then
    -- An embedded scene shifts every element level into its owner's band, for the span of this one spec apply.
    local owner = frame._msufPreviewScene
    local bias = owner.levelBase
    if bias then MSUF.UF.Layers.SetLevelBias(bias) end
    ok = GF.ApplySceneButton(frame, kind, canApplyDirty and dirtyMask or nil, owner.ignoreOocFade)
    if bias then MSUF.UF.Layers.SetLevelBias(0) end
  elseif canApplyDirty then
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

local function AcquirePreviewFrame(scene, parent)
  local free = scene.free
  local freeCount = #free
  local frame = free[freeCount]
  if frame then
    free[freeCount] = nil
  elseif scene.default then
    GF._previewFrameSerial = GF._previewFrameSerial + 1
    frame = PixelLayoutRegion(CreateFrame("Button", "MSUF_GFPreviewButton_" .. GF._previewFrameSerial, parent, "BackdropTemplate"))
    if frame.EnableMouse then frame:EnableMouse(false) end
  else
    frame = PixelLayoutRegion(CreateFrame("Button", nil, parent, "BackdropTemplate"))
    frame:EnableMouse(false)
    -- No show/hide hooks mark it visible, so the scene does.
    frame._msufPreviewScope, frame._msufPreviewScene, frame._msufCoreVisible = true, scene, true
  end

  frame._msufGFPreviewPooled = nil
  frame._msufGFPreviewDetached = true
  frame._msufGFPreviewApplyKey = nil
  frame._msufGFPreviewPositionKey = nil
  if frame:GetParent() ~= parent then frame:SetParent(parent) end
  return frame
end

local function EnsurePreviewFrame(scene, index, parent)
  local kind, t = scene.kind, scene.t
  local frames = t.frames[kind]
  if not frames then
    frames = {}
    t.frames[kind] = frames
  end
  local frame = frames[index]
  if not frame then
    frame = AcquirePreviewFrame(scene, parent)
    frames[index] = frame
  elseif frame:GetParent() ~= parent then
    frame:SetParent(parent)
  end

  frame._msufGFIsPreviewFrame = true
  frame._msufGFPreviewOwnerKind = kind
  local member = PreviewMember(scene, index)
  frame._msufGFPreviewIndex = member
  frame._msufGFKind = kind
  frame._msufGFEM2Kind = kind
  frame._msufIsGroupFrame = true
  frame.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ("gf_" .. kind)
  frame.configKey = "gf_" .. kind
  if scene.default then
    frame.MSUFUnitKey = "player"
    frame.unitKey = "player"
    if frame.SetAttribute then frame:SetAttribute("unit", "player") end
  else
    -- A scene frame holds no unit at all; its class portrait is its sample class.
    frame.MSUFUnitKey, frame.unitKey = nil, nil
    frame._msufPortraitSampleClass = PREVIEW_CLASSES[((member - 1) % #PREVIEW_CLASSES) + 1]
    -- The sample name is the frame's name from its first apply: the text runtime never asks who "player" is.
    frame._msufPreviewNameText = PREVIEW_NAMES[((member - 1) % #PREVIEW_NAMES) + 1]
  end
  return frame
end

local function PreparePreviewFrame(scene, index, layout, w, h, spacing, growth, upc, primary, blockW, blockH)
  local frame = EnsurePreviewFrame(scene, index, layout)
  SetPreviewFrameSize(frame, w, h)
  PositionPreviewFrame(frame, layout, index, scene.kind, w, h, spacing, growth, upc, primary, blockW, blockH)
  if not frame.MSUFSpec and frame.Hide then frame:Hide() end
  return frame
end

local function ApplyPreviewFrame(scene, index, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
  local kind = scene.kind
  local frame = PreparePreviewFrame(scene, index, layout, w, h, spacing, growth, upc, primary, blockW, blockH)
  ApplyPreviewSpecIfNeeded(frame, kind, reason, w, h, dirtyMask, expectedRevision)
  ApplyPreviewData(frame, index, kind)
  -- Menu dispel-overlay preview: only row 1 owns a native aura container, so
  -- the MSUF-drawn preview has to be re-stamped per row on every rebuild.
  -- One boolean read when no preview is active.
  if _G.MSUF_DispelOverlayPreviewMode == true then
    Dep("MSUF_ApplyDispelOverlayPreviewToFrame")(frame)
  end
  return true
end

local function QueuePreviewBuild(scene, serial, visibleCount, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
  if not (C_Timer and C_Timer.After) then
    for i = 1, visibleCount do
      ApplyPreviewFrame(scene, i, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
    end
    return true
  end
  local index = 1
  local function Step()
    if InCombat() then return end
    if CurrentSceneSerial(scene) ~= serial then return end
    if not scene.t.active[scene.kind] then return end
    local limit = min(visibleCount, index + PREVIEW_BUILD_SLICE_COUNT - 1)
    EnterScene(scene)
    for i = index, limit do
      ApplyPreviewFrame(scene, i, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
    end
    LeaveScene(scene)
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

local function QueuePreviewDataRefresh(scene, serial, frames, visibleCount)
  local kind = scene.kind
  if not (C_Timer and C_Timer.After) then
    for i = 1, visibleCount do ApplyPreviewData(frames[i], i, kind) end
    return true
  end
  local index = 1
  local function Step()
    if CurrentSceneSerial(scene) ~= serial then return end
    if not scene.t.active[kind] then return end
    local limit = min(visibleCount, index + PREVIEW_BUILD_SLICE_COUNT - 1)
    EnterScene(scene)
    for i = index, limit do ApplyPreviewData(frames[i], i, kind) end
    LeaveScene(scene)
    index = limit + 1
    if index <= visibleCount then C_Timer.After(0, Step) end
  end
  C_Timer.After(0, Step)
  return true
end

--- An embedded scene sits at its owner's frame level: container, layout and frames take the one base, and a frame
--- whose level moved applies its spec again so every element level follows (see Layers.SetLevelBias).
local function SeatSceneLevels(scene, container, layout, frames, count)
  local base = scene.levelBase
  if container._msufGFLevelBase ~= base then
    container._msufGFLevelBase = base
    container:SetFrameLevel(base)
    layout:SetFrameLevel(base)
  end
  for i = 1, count do
    local frame = frames[i]
    if frame and frame._msufGFLevelBase ~= base then
      frame._msufGFLevelBase = base
      frame:SetFrameLevel(base)
      frame._msufGFPreviewApplyKey = nil
    end
  end
end

local function ShowScene(scene, count, opts)
  local kind, t = scene.kind, scene.t
  count = floor((tonumber(count) or DefaultPreviewCount(kind)) + 0.5)
  if count < 1 then count = DefaultPreviewCount(kind) end
  local visibleCount = VisiblePreviewCount(kind, count)
  opts = type(opts) == "table" and opts or nil

  t.active[kind] = true
  if scene.default and GF.ShowAdditionalGroupPreview then GF.ShowAdditionalGroupPreview(kind, count) end
  t.count[kind] = count
  local serial = BumpSceneSerial(scene)

  local container, layout, w, h, spacing, growth, upc, primary, blockW, blockH = PositionContainer(scene, count)
  local frames = t.frames[kind] or {}
  t.frames[kind] = frames
  for i = 1, visibleCount do
    PreparePreviewFrame(scene, i, layout, w, h, spacing, growth, upc, primary, blockW, blockH)
  end
  for i = #frames, visibleCount + 1, -1 do
    ReleasePreviewFrame(scene, frames, i)
  end
  if scene.levelBase then SeatSceneLevels(scene, container, layout, frames, visibleCount) end
  container:Show()
  local reason = opts and opts.reason or "MSUF_GF_PREVIEW"
  local dirtyMask = opts and opts.dirtyMask or nil
  local expectedRevision = PreviewApplyRevision(kind)
  if dirtyMask == nil and PreviewSpecsCurrent(frames, visibleCount, kind, w, h, expectedRevision) then
    if opts and opts.immediate == true or visibleCount <= PREVIEW_BUILD_SLICE_THRESHOLD then
      for i = 1, visibleCount do ApplyPreviewData(frames[i], i, kind) end
    else
      QueuePreviewDataRefresh(scene, serial, frames, visibleCount)
    end
    return true
  end
  if opts and opts.immediate == true or visibleCount <= PREVIEW_BUILD_SLICE_THRESHOLD then
    for i = 1, visibleCount do
      ApplyPreviewFrame(scene, i, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
    end
  else
    QueuePreviewBuild(scene, serial, visibleCount, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
  end
  return true
end

function GF.ShowPreview(kind, count, opts)
  if InCombat() then return false end
  if type(PreviewsAllowed) == "function" and not PreviewsAllowed() then return false end
  kind = NormalizeKind(kind) or "party"
  return ShowScene(defaultScenes[kind], count, opts)
end

local function HideScene(scene)
  local kind, t = scene.kind, scene.t
  if scene.default and GF.HideAdditionalGroupPreview then GF.HideAdditionalGroupPreview(kind) end
  local container = t.container[kind]
  local frames = t.frames[kind]
  if t.active[kind] ~= true
    and (not (container and container.IsShown and container:IsShown()))
    and not (frames and #frames > 0) then
    return true
  end
  local serial = t.serial
  serial[kind] = (serial[kind] or 0) + 1
  t.active[kind] = nil
  t.count[kind] = nil
  if frames then
    for i = #frames, 1, -1 do
      ReleasePreviewFrame(scene, frames, i)
    end
  end
  if container then container:Hide() end
  --- Hand the block border back to the live anchor: it was force-hidden for as
  --- long as this preview owned the block.
  if scene.default and type(GF.ApplyGroupBorder) == "function" then GF.ApplyGroupBorder(kind) end
  return true
end

function GF.HidePreview(kind)
  kind = NormalizeKind(kind) or "party"
  return HideScene(defaultScenes[kind])
end

--- Combat is a hard ownership boundary for the visual-only preview pool. The
--- options/edit-mode owner may still be logically open when combat starts, so
--- detach every preview immediately, the isolated scenes included. The result
--- says whether a default preview hid: only those retire a live header, so the
--- caller hands the blocks back for them alone. An isolated scene suppresses no
--- header and never sets it.
function GF.HidePreviewsForCombat()
  local hidden = false
  for i = 1, #PREVIEW_KINDS do
    local kind = PREVIEW_KINDS[i]
    local frames = GF._previewFrames[kind]
    if GF._previewActive[kind] == true or (frames and #frames > 0) then
      hidden = HideScene(defaultScenes[kind]) or hidden
    end
  end
  if isolatedSceneCount > 0 then
    for scene in pairs(isolatedScenes) do
      local frames = scene.t.frames[scene.kind]
      if scene.t.active[scene.kind] == true or (frames and #frames > 0) then
        HideScene(scene)
      end
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

--- Scene API. GF.NewPreviewScene(parent) returns a scene root: a preview kit host (MSUF_UF_PreviewKit.lua)
--- that owns the isolated group scenes of one surface. root:Group(kind, count) makes (or re-shows) the group
--- scene of that kind: `count` plain Buttons laid out like the live grid and painted with static sample data
--- (the Edit Mode dummies' fake roster, no unit query), parented to `parent`. Whoever owns `parent` places and
--- scales it. root:Unit(unitKey) makes the static scene of one unit frame the same way (MSUF_UF_UnitScene.lua).
---
--- Lifecycle: nothing shows or listens until root:Activate(). While active the root listens for CONFIG_APPLIED,
--- PLAYER_REGEN_ENABLED and PLAYER_REGEN_DISABLED. The first two answer with one coalesced repaint (root:Request) on
--- the next frame; the third hides the unit scenes. root:Deactivate() hides every scene (keeping what each wants)
--- and drops the three subscriptions. Combat hides the groups (GF.HidePreviewsForCombat) like every other preview
--- and the regen repaint brings the scenes back.
local SceneRoot = {}
SceneRoot.__index = SceneRoot
local rootSerial = 0

local function RootAllowed(host)
  return not InCombat()
end

local function RootPaint(host, reason)
  local reasonText = reason == "config" and "MSUF_GF_PREVIEW_REFRESH" or "MSUF_GF_PREVIEW"
  for _, group in pairs(host.root.groups) do
    local want = group.want
    if want then group:Show(want, { reason = reasonText }) end
  end
  for _, unitScene in pairs(host.root.units) do
    if unitScene.want then unitScene:Show() end
  end
end

local function RootActivate(host)
  local root = host.root
  local bus = MSUF.EventBus
  local key = root.eventKey
  bus:Register("CONFIG_APPLIED", key, root.onConfig)
  bus:Register("PLAYER_REGEN_ENABLED", key, root.onRegen)
  bus:Register("PLAYER_REGEN_DISABLED", key, root.onCombat)
end

local function RootDeactivate(host)
  local root = host.root
  local bus = MSUF.EventBus
  bus:Unregister("CONFIG_APPLIED", root.eventKey)
  bus:Unregister("PLAYER_REGEN_ENABLED", root.eventKey)
  bus:Unregister("PLAYER_REGEN_DISABLED", root.eventKey)
  for _, group in pairs(root.groups) do HideScene(group) end
  for _, unitScene in pairs(root.units) do unitScene:Conceal() end
end

function GF.NewPreviewScene(parent)
  rootSerial = rootSerial + 1
  local Kit = Dep("MSUF").UF.PreviewKit
  assert(Kit, "MSUF: missing required dependency 'UF.PreviewKit' required by UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
  local root = setmetatable({ parent = parent, groups = {}, units = {}, eventKey = "MSUF.GF.PreviewScene." .. rootSerial }, SceneRoot)
  root.host = Kit.NewHost(parent, {
    activate = RootActivate, deactivate = RootDeactivate, paint = RootPaint, allowed = RootAllowed,
  })
  root.host.root = root
  -- One closure per root, registered only while the root is active.
  root.onConfig = function() root.host:Request("config") end
  root.onRegen = function() root.host:Request("regen") end
  -- Combat hides the unit scenes at once; the regen repaint brings the wanted ones back.
  root.onCombat = function()
    for _, unitScene in pairs(root.units) do unitScene:Conceal() end
  end
  return root
end

function SceneRoot:Group(kind, count, opts)
  kind = NormalizeKind(kind)
  if not kind then return nil end
  local group = self.groups[kind]
  if not group then
    group = NewScene(kind)
    group.root = self
    self.groups[kind] = group
    group:SetParent(self.parent)
  end
  if count then
    group.want = count
    if self.host.active then group:Show(count, opts) end
  end
  return group
end

--- The static unit scene of a unit key (docs/PREVIEW_RUNTIME_RULES.md, "Unit preview scenes"); nil when this client has
--- no such frame. opts.sample overrides fields of the unit's sample, opts.show shows it at once.
function SceneRoot:Unit(unitKey, opts)
  local UnitScene = Dep("MSUF").UF.UnitScene
  assert(UnitScene, "MSUF: missing required dependency 'UF.UnitScene' required by UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
  local unit = UnitScene.Normalize(unitKey)
  if not unit then return nil end
  opts = type(opts) == "table" and opts or nil
  local scene = self.units[unit]
  if not scene then
    scene = UnitScene.New(self, unit, opts and opts.sample)
    self.units[unit] = scene
  elseif opts and opts.sample ~= nil then
    scene:SetSample(opts.sample)
  end
  if opts and opts.show == true then scene:Show() end
  return scene
end

function SceneRoot:Activate() return self.host:Activate() end
function SceneRoot:Deactivate() return self.host:Deactivate() end
SceneRoot.Hide = SceneRoot.Deactivate
function SceneRoot:IsActive() return self.host.active == true end

--- Ask for a repaint on the next frame (many requests, one paint). Ignored while the root is inactive.
function SceneRoot:Request(reason) return self.host:Request(reason) end

--- An owner that runs its own animation driver hands the clock over: a number animates every group at that
--- elapsed time, nil returns the groups to their static sample. The active groups repaint, unless the owner is
--- about to show or refresh them itself (noRefresh).
function SceneRoot:SetClock(elapsed, noRefresh)
  local animating = elapsed ~= nil
  if animating then self.elapsed = elapsed end
  self.animating = animating or nil
  if noRefresh == true then return end
  for _, group in pairs(self.groups) do
    if group.t.active[group.kind] == true then group:RefreshData() end
  end
end

function SceneRoot:SetParent(parent)
  self.parent = parent
  for _, group in pairs(self.groups) do group:SetParent(parent) end
  for _, unitScene in pairs(self.units) do unitScene:SetParent(parent) end
end

function SceneRoot:SetLayerFilter(visible, solo)
  for _, group in pairs(self.groups) do group:SetLayerFilter(visible, solo) end
end

--- Deactivate the root and forget its groups. Their frames go with them; build one root and keep it.
function SceneRoot:Release()
  self.host:Deactivate()
  for kind, group in pairs(self.groups) do
    isolatedScenes[group] = nil
    isolatedSceneCount = isolatedSceneCount - 1
    self.groups[kind] = nil
  end
  for unit, unitScene in pairs(self.units) do
    unitScene:Release()
    self.units[unit] = nil
  end
end

--- The root owns what is on screen: while it is inactive a direct Show only records the wanted count, which
--- Activate paints.
function Scene:Show(count, opts)
  self.want = count
  local root = self.root
  if InCombat() or (root and root.host.active ~= true) then return false end
  EnterScene(self)
  local shown = ShowScene(self, count, opts)
  LeaveScene(self)
  return shown
end

--- An explicit hide forgets the wanted count: only combat hides a group without forgetting it, so the root
--- brings it back when combat ends.
function Scene:Hide()
  self.want = nil
  return HideScene(self)
end

function Scene:Refresh(opts)
  if InCombat() or self.t.active[self.kind] ~= true then return false end
  opts = type(opts) == "table" and opts or nil
  return self:Show(self.t.count[self.kind] or DefaultPreviewCount(self.kind), {
    reason = opts and opts.reason or "MSUF_GF_PREVIEW_REFRESH",
    dirtyMask = opts and opts.dirtyMask or nil,
    immediate = opts and opts.immediate == true or nil,
  })
end

--- Seed the fake data again (an animation tick, a layer change); no layout and no spec apply.
function Scene:RefreshData()
  local kind, t = self.kind, self.t
  if InCombat() or t.active[kind] ~= true then return false end
  local frames = t.frames[kind]
  local refreshed = false
  EnterScene(self)
  for i = 1, VisiblePreviewCount(kind, t.count[kind] or DefaultPreviewCount(kind)) do
    local frame = frames[i]
    if frame and frame.IsShown and frame:IsShown() then
      ApplyPreviewData(frame, i, kind)
      refreshed = true
    end
  end
  LeaveScene(self)
  return refreshed
end

function Scene:RefreshAuras()
  if InCombat() then return false end
  EnterScene(self)
  local refreshed = RefreshSceneAuras(self)
  LeaveScene(self)
  return refreshed
end

function Scene:RefreshSpellIndicators()
  if InCombat() then return false end
  EnterScene(self)
  local refreshed = RefreshSceneSpellIndicators(self)
  LeaveScene(self)
  return refreshed
end

--- The layers this scene draws, same contract as GF.SetPreviewLayerFilter: `visible[key] == false` hides a
--- layer, `solo` shows only that one. Callers push on change; the shown frames are re-seeded at once.
function Scene:SetLayerFilter(visible, solo)
  if type(visible) ~= "table" then visible = nil end
  if type(solo) ~= "string" or PREVIEW_LAYER_KEYS[solo] ~= true then solo = nil end
  self.layerVisible, self.layerSolo = visible, solo
  return self:RefreshData()
end

--- Zoom the whole scene: the frames keep their spec size, the container carries the scale.
function Scene:SetScale(scale)
  scale = tonumber(scale)
  if not (scale and scale > 0) then scale = 1 end
  if self.scale == scale then return false end
  self.scale = scale
  local container = self.t.container[self.kind]
  if container and container._msufGFPreviewScale ~= scale then
    container._msufGFPreviewScale = scale
    container:SetScale(scale)
  end
  return true
end

--- The frame level the scene sits at (its owner's); element levels are shifted by the same base.
function Scene:SetLevel(base)
  base = tonumber(base)
  if self.levelBase == base then return false end
  self.levelBase = base
  return true
end

--- Several settings in one call, without a repaint: the next Show or Refresh paints them. Fields: scale, level,
--- role, sample, bodyOnly, layerVisible, layerSolo (see the setters of the same names), ignoreOocFade (the owner's
--- window is always open out of combat, so the scene shows no out-of-combat fade; every other alpha setting stays) and
--- fit (the container is the size of one frame instead of the layout's grid footprint, for an owner that shows a
--- single frame and centres the container itself).
function Scene:Configure(opts)
  if opts.scale ~= nil then self:SetScale(opts.scale) end
  if opts.level ~= nil then self:SetLevel(opts.level) end
  if opts.role ~= nil then
    local role = opts.role
    if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then role = nil end
    if self.role ~= role then
      self.role = role
      local frames = self.t.frames[self.kind]
      for i = 1, frames and #frames or 0 do frames[i]._msufGFPreviewApplyKey = nil end
    end
  end
  if opts.sample ~= nil then self.sample = type(opts.sample) == "table" and opts.sample or nil end
  if opts.fit ~= nil then self.fit = opts.fit == true or nil end
  if opts.ignoreOocFade ~= nil then
    local ignore = opts.ignoreOocFade == true or nil
    if self.ignoreOocFade ~= ignore then
      self.ignoreOocFade = ignore
      local frames = self.t.frames[self.kind]
      for i = 1, frames and #frames or 0 do frames[i]._msufGFPreviewApplyKey = nil end
    end
  end
  if opts.bodyOnly ~= nil then self.bodyOnly = opts.bodyOnly == true or nil end
  if opts.layerVisible ~= nil or opts.layerSolo ~= nil then
    self.layerVisible = type(opts.layerVisible) == "table" and opts.layerVisible or nil
    self.layerSolo = type(opts.layerSolo) == "string" and PREVIEW_LAYER_KEYS[opts.layerSolo] == true and opts.layerSolo or nil
  end
end

--- Pin one sample for every row of the scene: { name, class, hpPct, powerPct, hpMax, powerMax, absorb, healPct,
--- absorbPct, healAbsorbPct, tempMaxPct, powerColor = { r, g, b } } (any field optional; fractions 0..1, maxima the
--- bar and text scale, absorb the amount the absorb texts show).
--- nil clears it.
function Scene:SetSample(sample)
  if type(sample) ~= "table" then sample = nil end
  self.sample = sample
  return self:RefreshData()
end

--- Body only: the scene paints the frame itself (bars, texts, border, prediction) and leaves status icons, auras,
--- spell indicators and the threat sample to the owner's own widgets.
function Scene:SetBodyOnly(on)
  on = on == true
  if (self.bodyOnly == true) == on then return false end
  self.bodyOnly = on or nil
  return self:RefreshData()
end

--- The role every frame of this scene lays out for (the power bar follows the role filters). nil, the default,
--- gives each row its own sample role: tank, healer, damage, damage, healer, and so on.
function Scene:SetRole(role)
  if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then role = nil end
  if self.role == role then return false end
  self.role = role
  local frames = self.t.frames[self.kind]
  for i = 1, frames and #frames or 0 do frames[i]._msufGFPreviewApplyKey = nil end
  return self:Refresh({ immediate = true })
end

function Scene:Frames() return self.t.frames[self.kind] end
function Scene:Container() return self.t.container[self.kind] end
function Scene:Layout() return self.t.layout[self.kind] end
function Scene:IsActive() return self.t.active[self.kind] == true end
function Scene:Count() return ActivePreviewCount(self) end

PreviewsAllowed = function()
  if _G.MSUF_UnitEditModeActive == true then return true end
  return _G.MSUF2_GFPagePreviewActive == true
end

ExportPublic("MSUF_GF_ShowPreview", function(kind, count) return GF.ShowPreview(kind, count) end)
ExportPublic("MSUF_GF_HidePreview", function(kind) return GF.HidePreview(kind) end)
ExportPublic("MSUF_GF_SetPreviewAnchor", function(kind, parent) return GF.SetPreviewAnchor(kind, parent) end)
ExportPublic("MSUF_GF_RefreshPreviewLayout", function(kind, opts) return GF.RefreshPreviewLayout(kind, opts) end)
ExportPublic("MSUF_GF_RefreshPreviewBox", _G.MSUF_GF_RefreshPreviewLayout)
ExportPublic("MSUF_GF_RefreshPreviewAuras", function(kind) return GF.RefreshPreviewAuras(kind) end)
ExportPublic("MSUF_GF_RefreshPreviewSpellIndicators", function(kind) return GF.RefreshPreviewSpellIndicators(kind) end)
ExportPublic("MSUF_GF_RefreshPreviewAnimation", function() return GF.RefreshPreviewAnimation() end)
