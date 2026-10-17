--- UnitFrames/Engine/MSUF_UF_PreviewKit.lua
--- The lifecycle and frame pools every preview surface shares. Client-neutral: it reads no addon setting and
--- registers no event or OnUpdate script of its own.
--- Host interface, timers and lifecycle rules: docs/PREVIEW_RUNTIME_RULES.md ("Preview kit").
local _, MSUF = ...
MSUF.UF = MSUF.UF or {}
local Kit = {}
MSUF.UF.PreviewKit = Kit

local setmetatable, pairs = setmetatable, pairs
local C_Timer = C_Timer

local function DefaultAfter(delay, fn)
  C_Timer.After(delay, fn)
end

------------------------------------------------------------------------------------------------ host

local Host = {}
Host.__index = Host

function Kit.NewHost(parent, opts)
  opts = opts or {}
  local host = setmetatable({
    parent = parent, opts = opts, pools = {}, acquired = {}, after = opts.after or DefaultAfter,
  }, Host)
  -- One closure per host; a repaint request allocates nothing.
  host.run = function()
    if not host.queued then return end
    host.queued = nil
    local reason = host.reason
    host.reason = nil
    host:Refresh(reason)
  end
  return host
end

function Host:IsActive()
  return self.active == true
end

function Host:Activate()
  if self.active then return false end
  self.active = true
  local opts = self.opts
  if not self.built then
    self.built = true
    if opts.build then opts.build(self) end
  end
  if opts.activate then opts.activate(self) end
  self:Refresh("activate")
  return true
end

function Host:Deactivate()
  if not self.active then return false end
  self.active = false
  -- A queued repaint finds its request cleared and ends.
  self.queued, self.reason = nil, nil
  local opts = self.opts
  if opts.deactivate then opts.deactivate(self) end
  for kind in pairs(self.acquired) do self:ReleaseAll(kind) end
  return true
end

function Kit.CopyPlain(value)
  assert(not (issecretvalue and issecretvalue(value)), "preview input must be public")
  if type(value) ~= "table" then return value end
  local copy = {}
  for key, child in pairs(value) do copy[Kit.CopyPlain(key)] = Kit.CopyPlain(child) end
  return copy
end

function Host:Refresh(reason)
  if not self.active then return false end
  local allowed = self.opts.allowed
  if allowed and not allowed(self) then return false end
  self.opts.paint(self, reason)
  return true
end

function Host:Request(reason)
  if not self.active then return false end
  if self.opts.allowed and not self.opts.allowed(self) then return false end
  if reason ~= nil then self.reason = reason end
  if self.queued then return true end
  self.queued = true
  self.after(0, self.run)
  return true
end

function Host:Acquire(kind)
  local pool, list = self.pools[kind], self.acquired[kind]
  if not pool then
    pool, list = {}, {}
    self.pools[kind], self.acquired[kind] = pool, list
  end
  local count = #pool
  local object = pool[count]
  if object then
    pool[count] = nil
  else
    object = self.opts.create(kind, self)
  end
  list[#list + 1] = object
  return object
end

local function Reset(host, kind, object)
  local reset = host.opts.reset
  if reset then
    reset(kind, object)
  elseif object.Hide then
    object:Hide()
  end
end

function Host:Release(kind, object)
  local list, pool = self.acquired[kind], self.pools[kind]
  if not list then return false end
  for index = #list, 1, -1 do
    if list[index] == object then
      table.remove(list, index)
      Reset(self, kind, object)
      pool[#pool + 1] = object
      return true
    end
  end
  return false
end

function Host:ReleaseAll(kind)
  local list, pool = self.acquired[kind], self.pools[kind]
  if not list then return end
  for index = #list, 1, -1 do
    local object = list[index]
    list[index] = nil
    Reset(self, kind, object)
    pool[#pool + 1] = object
  end
end
