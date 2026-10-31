--- Per-scene lifecycle, wanted state, serials, deferred builds and default-scene compatibility.
local addonName, MSUF = ...
local GF = MSUF.GF
local Layout = assert(GF.PreviewLayout, "Group preview requires PreviewLayout")
local ActivePreviewCount = Layout.ActivePreviewCount
local DefaultPreviewCount = Layout.DefaultPreviewCount
local NormalizeKind = Layout.NormalizeKind
local PositionContainer = Layout.PositionContainer
local VisiblePreviewCount = Layout.VisiblePreviewCount
local Samples = assert(GF.PreviewSamples, "Group preview requires PreviewSamples")
local ApplyPreviewData = Samples.ApplyPreviewData
local Pool = assert(GF.PreviewPool, "Group preview requires PreviewPool")
local ApplyPreviewFrame = Pool.ApplyPreviewFrame
local InvalidateFrames = Pool.InvalidateFrames
local PreparePreviewFrame = Pool.PreparePreviewFrame
local PreviewApplyRevision = Pool.PreviewApplyRevision
local PreviewSpecsCurrent = Pool.PreviewSpecsCurrent
local ReleasePreviewFrame = Pool.ReleasePreviewFrame
local SeatSceneLevels = Pool.SeatSceneLevels
local Style = assert(GF.PreviewStyle, "Group preview requires PreviewStyle")
local InCombat = Style.InCombat
local PREVIEW_LAYER_KEYS = Style.PREVIEW_LAYER_KEYS
local Auras = assert(GF.PreviewAuras, "Group preview requires PreviewAuras")
local RefreshSceneAuras = Auras.RefreshSceneAuras
local Indicators = assert(GF.PreviewIndicators, "Group preview requires PreviewIndicators")
local RefreshSceneSpellIndicators = Indicators.RefreshSceneSpellIndicators
local C_Timer = C_Timer
local floor = math.floor
local min = math.min
local type = type
local tonumber = tonumber
local tostring = tostring

local function PreviewsAllowed()
  if MSUF_UnitEditModeActive == true then return true end
  return MSUF.PublicGlobals.MSUF2_GFPagePreviewActive == true
end

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
  scene.portraitSpecMeta, scene.portraitConfigMeta = {}, {}
  scene.portraitSampleSpec = setmetatable({ portrait = setmetatable({}, scene.portraitConfigMeta) }, scene.portraitSpecMeta)
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

local function RefreshActivePreviewKinds(refresh, opts)
  local any = false
  for i = 1, #PREVIEW_KINDS do
    local activeKind = PREVIEW_KINDS[i]
    if GF._previewActive and GF._previewActive[activeKind] then
      any = refresh(activeKind, opts) or any
    end
  end
  return any
end

function GF.RefreshPreviewAuras(kind)
  if InCombat() then return false end
  if kind == nil then return RefreshActivePreviewKinds(GF.RefreshPreviewAuras) end
  kind = NormalizeKind(kind)
  if not kind then return false end
  return RefreshSceneAuras(defaultScenes[kind])
end
function GF.RefreshPreviewSpellIndicators(kind)
  if InCombat() then return false end
  if kind == nil then return RefreshActivePreviewKinds(GF.RefreshPreviewSpellIndicators) end
  kind = NormalizeKind(kind)
  if not kind then return false end
  return RefreshSceneSpellIndicators(defaultScenes[kind])
end

--- Menu -> engine bridge for the LAYERS rail. The menu owns the switches; this
--- only mirrors them onto the in-world dummies and re-seeds the frames already
--- on screen. Callers push on every preview refresh, so the signature compare
--- is what keeps that from re-seeding forty frames per mouse-over.
function GF.SetPreviewLayerFilter(visible, solo)
  if type(visible) ~= "table" then visible = nil end
  if type(solo) ~= "string" or PREVIEW_LAYER_KEYS[solo] ~= true then solo = nil end
  for i = 1, #PREVIEW_KINDS do
    local scene = defaultScenes[PREVIEW_KINDS[i]]
    scene.layerVisible, scene.layerSolo = visible, solo
  end
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
          ApplyPreviewData(frame, index, kind, defaultScenes[kind])
          reseeded = true
        end
      end
    end
  end
  return reseeded
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
    for i = index, limit do
      ApplyPreviewFrame(scene, i, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
    end
    index = limit + 1
    if index <= visibleCount then
      C_Timer.After(0, Step)
    end
  end
  C_Timer.After(0, Step)
  return true
end
local function QueuePreviewDataRefresh(scene, serial, frames, visibleCount)
  local kind = scene.kind
  if not (C_Timer and C_Timer.After) then
    for i = 1, visibleCount do ApplyPreviewData(frames[i], i, kind, scene) end
    return true
  end
  local index = 1
  local function Step()
    if CurrentSceneSerial(scene) ~= serial then return end
    if not scene.t.active[kind] then return end
    local limit = min(visibleCount, index + PREVIEW_BUILD_SLICE_COUNT - 1)
    for i = index, limit do ApplyPreviewData(frames[i], i, kind, scene) end
    index = limit + 1
    if index <= visibleCount then C_Timer.After(0, Step) end
  end
  C_Timer.After(0, Step)
  return true
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
      for i = 1, visibleCount do ApplyPreviewData(frames[i], i, kind, scene) end
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
  if kind == nil then return RefreshActivePreviewKinds(GF.RefreshPreviewLayout, opts) end
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
            ApplyPreviewData(frame, i, kind, defaultScenes[kind])
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

--- The root owns what is on screen: while it is inactive a direct Show only records the wanted count, which
--- Activate paints.
function Scene:Show(count, opts)
  self.want = count
  local root = self.root
  if InCombat() or (root and root.host.active ~= true) then return false end
  local shown = ShowScene(self, count, opts)
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
  for i = 1, VisiblePreviewCount(kind, t.count[kind] or DefaultPreviewCount(kind)) do
    local frame = frames[i]
    if frame and frame.IsShown and frame:IsShown() then
      ApplyPreviewData(frame, i, kind, self)
      refreshed = true
    end
  end
  return refreshed
end

function Scene:RefreshAuras()
  if InCombat() then return false end
  local refreshed = RefreshSceneAuras(self)
  return refreshed
end

function Scene:RefreshSpellIndicators()
  if InCombat() then return false end
  local refreshed = RefreshSceneSpellIndicators(self)
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
  InvalidateFrames(self.t.frames[self.kind])
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
      InvalidateFrames(frames)
    end
  end
  if opts.sample ~= nil then self.sample = type(opts.sample) == "table" and opts.sample or nil end
  if opts.fit ~= nil then self.fit = opts.fit == true or nil end
  if opts.ignoreOocFade ~= nil then
    local ignore = opts.ignoreOocFade == true or nil
    if self.ignoreOocFade ~= ignore then
      self.ignoreOocFade = ignore
      local frames = self.t.frames[self.kind]
      InvalidateFrames(frames)
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
--- bar and text scale, absorb the amount the absorb texts show). Optional portrait = { shown, texture, l, r, t, b }
--- and statusRegions = { { field, shown, text, texture, l, r, t, b }, ... } carry public owner-selected samples;
--- the scene alone paints these regions and applies its portrait/status layer filters.
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
  InvalidateFrames(frames)
  return self:Refresh({ immediate = true })
end

function Scene:Frames() return self.t.frames[self.kind] end
function Scene:Container() return self.t.container[self.kind] end
function Scene:Layout() return self.t.layout[self.kind] end
function Scene:IsActive() return self.t.active[self.kind] == true end
function Scene:Count() return ActivePreviewCount(self) end


-- Releasing a kit root removes only that root's scenes from the combat registry.
local function ReleaseScene(scene)
  if isolatedScenes[scene] then
    isolatedScenes[scene] = nil
    isolatedSceneCount = isolatedSceneCount - 1
  end
end

GF.PreviewScenes = {
  New = NewScene,
  Default = defaultScenes,
  Hide = HideScene,
  Release = ReleaseScene,
}
