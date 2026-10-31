--- Public preview-kit roots; the group scenes own their own pool, layout and sample state.
local addonName, MSUF = ...
local GF = MSUF.GF
local Scenes = assert(GF.PreviewScenes, "Group preview requires PreviewScenes")
local HideScene = Scenes.Hide
local NewScene = Scenes.New
local Style = assert(GF.PreviewStyle, "Group preview requires PreviewStyle")
local InCombat = Style.InCombat
local Layout = assert(GF.PreviewLayout, "Group preview requires PreviewLayout")
local NormalizeKind = Layout.NormalizeKind
local issecretvalue = issecretvalue
local type = type
local ExportPublic = MSUF.ExportPublic

-- Resolve forward/cold exports at use time, preserving the existing dependency boundary.
local function Dep(name)
  return MSUF.Require(name, "UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
end

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
  for _, surface in pairs(host.root.surfaces) do surface:Refresh() end
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
  for _, surface in pairs(root.surfaces) do surface:Suspend() end
end

function GF.NewPreviewScene(parent)
  rootSerial = rootSerial + 1
  local Kit = Dep("MSUF").UF.PreviewKit
  assert(Kit, "MSUF: missing required dependency 'UF.PreviewKit' required by UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
  local root = setmetatable({ parent = parent, groups = {}, units = {}, surfaces = {}, eventKey = "MSUF.GF.PreviewScene." .. rootSerial }, SceneRoot)
  root.host = Kit.NewHost(parent, {
    activate = RootActivate, deactivate = RootDeactivate, paint = RootPaint, allowed = RootAllowed,
  })
  root.host.root = root
  -- One closure per root, registered only while the root is active.
  root.onConfig = function() root.host:Request("config") end
  root.onRegen = function() root.host:Request("regen") end
  -- Combat hides the unit scenes and suspends the surfaces at once; the regen repaint brings the wanted ones back.
  root.onCombat = function()
    for _, unitScene in pairs(root.units) do unitScene:Conceal() end
    for _, surface in pairs(root.surfaces) do surface:Suspend() end
  end
  return root
end

local function Surface(root, kind, key, opts)
  assert(not (issecretvalue and issecretvalue(key)), "preview key must be public")
  assert(not (issecretvalue and issecretvalue(opts)), "preview options must be public")
  local id = kind .. ":" .. key
  local scene = root.surfaces[id]
  if not scene then
    scene = MSUF.UF.PreviewSurfaces.New(root, kind, key, opts)
    root.surfaces[id] = scene
  elseif opts then
    scene.want = true
    scene:SetOptions(opts)
    return scene
  end
  scene:Show()
  return scene
end

function SceneRoot:Castbar(unitKey, opts) return Surface(self, "Castbar", unitKey, opts) end
function SceneRoot:ClassPower(opts) return Surface(self, "ClassPower", "player", opts) end

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

--- An owner that runs its own animation driver hands the clock over: a number animates groups and opted-in castbars at that
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
  for _, surface in pairs(self.surfaces) do
    if surface.opts.animate then surface:Refresh() end
  end
  for _, scene in pairs(self.units) do scene:RefreshData(false) end
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
    Scenes.Release(group)
    self.groups[kind] = nil
  end
  for unit, unitScene in pairs(self.units) do
    unitScene:Release()
    self.units[unit] = nil
  end
  for key in pairs(self.surfaces) do self.surfaces[key] = nil end
end
ExportPublic("MSUF_GF_ShowPreview", function(kind, count) return GF.ShowPreview(kind, count) end)
ExportPublic("MSUF_GF_HidePreview", function(kind) return GF.HidePreview(kind) end)
ExportPublic("MSUF_GF_SetPreviewAnchor", function(kind, parent) return GF.SetPreviewAnchor(kind, parent) end)
ExportPublic("MSUF_GF_RefreshPreviewLayout", function(kind, opts) return GF.RefreshPreviewLayout(kind, opts) end)
ExportPublic("MSUF_GF_RefreshPreviewBox", MSUF.Require("MSUF_GF_RefreshPreviewLayout", "UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua"))
ExportPublic("MSUF_GF_RefreshPreviewAuras", function(kind) return GF.RefreshPreviewAuras(kind) end)
ExportPublic("MSUF_GF_RefreshPreviewSpellIndicators", function(kind) return GF.RefreshPreviewSpellIndicators(kind) end)
ExportPublic("MSUF_GF_RefreshPreviewAnimation", function() return GF.RefreshPreviewAnimation() end)
