local _, MSUF = ...
local Kit = MSUF.UF.PreviewKit
local Surfaces = {}
MSUF.UF.PreviewSurfaces = Surfaces
local Scene = {}
Scene.__index = Scene

local function Allowed(host)
  return host.scene.root:IsActive() and not InCombatLockdown()
end

local function Paint(host)
  local scene = host.scene
  if not scene.want then return end
  if not scene.frame then scene.frame = host:Acquire("surface") end
  scene.frame:SetParent(scene.root.parent)
  Surfaces[scene.kind].Paint(scene)
end

local function Create(_, host)
  return Surfaces[host.scene.kind].Create(host.scene)
end

local function Deactivate(host)
  host.scene.frame = nil
end

function Surfaces.New(root, kind, key, opts)
  local scene = setmetatable({ root = root, kind = kind, key = key, want = true }, Scene)
  scene.host = Kit.NewHost(root.parent, { create = Create, paint = Paint, allowed = Allowed, deactivate = Deactivate })
  scene.host.scene = scene
  scene.opts = Kit.CopyPlain(opts) or {}
  return scene
end

function Scene:SetOptions(opts)
  self.opts = Kit.CopyPlain(opts) or {}
  return self:Refresh()
end

function Scene:Refresh()
  if not self.want or not Allowed(self.host) then return false end
  if not self.host.active then return self.host:Activate() end
  return self.host:Refresh("scene")
end

function Scene:Show()
  self.want = true
  return self:Refresh()
end

function Scene:Suspend() return self.host:Deactivate() end
function Scene:Hide()
  self.want = false
  return self:Suspend()
end
function Scene:Frame() return self.frame end
function Scene:IsActive() return self.host.active == true end
